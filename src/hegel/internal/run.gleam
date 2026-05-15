import gbor
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{ProcessDown}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import hegel/internal/case_worker
import hegel/internal/cbor
import hegel/internal/protocol
import hegel/internal/recorder
import hegel/internal/session
import hegel/internal/test_case.{type TestCase}
import logging

pub type InternalError {
  InternalError(stream_id: Option(Int), reason: String)
}

pub type TestRunResult {
  TestRunResult(
    passed: Bool,
    failure_message: Option(String),
    failure_drawn_entries: List(recorder.DrawnEntry),
    valid_count: Int,
    total_count: Int,
    invalid_count: Int,
    interesting_count: Int,
    seed: String,
    // Server-reported error wrappers
    server_error: Option(String),
    health_check_failure: Option(String),
    flaky: Option(String),
  )
}

pub type RunMessage {
  S1Packet(protocol.Packet)
  CaseOutcome(case_worker.Outcome)
  CaseCrashed(process.Down)
}

type RunState {
  RunState(
    reply_to: process.Subject(Result(TestRunResult, InternalError)),
    session: process.Subject(session.SessionMessage),
    test_stream: session.Stream,
    in_flight: Dict(Int, process.Monitor),
    failure_message: Option(String),
    failure_drawn_entries: List(recorder.DrawnEntry),
    test_done: Option(TestRunResult),
    test_fn: fn(TestCase) -> Nil,
    outcomes: process.Subject(case_worker.Outcome),
    replays_remaining: Int,
  )
}

pub fn extract_panic_message(exc) {
  case_worker.extract_panic_message(exc)
}

pub fn internal_panic(message: String) -> a {
  case_worker.internal_panic(message)
}

fn encode_reply(value: gbor.CBOR) -> BitArray {
  cbor.encode(cbor.cbor_map([#("result", value)]))
}

fn build_selector(
  test_stream: session.Stream,
  outcomes: process.Subject(case_worker.Outcome),
) -> process.Selector(RunMessage) {
  process.new_selector()
  |> process.select_map(test_stream.subject, S1Packet)
  |> process.select_map(outcomes, CaseOutcome)
  |> process.select_monitors(CaseCrashed)
}

type TestCaseEvent {
  TestCaseEvent(stream_id: Int, is_final: Bool)
}

fn decode_test_case_event(payload: BitArray) -> TestCaseEvent {
  let decoder = {
    use stream_id <- decode.field("stream_id", decode.int)
    use is_final <- decode.field("is_final", decode.bool)
    decode.success(TestCaseEvent(stream_id:, is_final:))
  }
  case cbor.decode_bytes(payload, decoder) {
    Ok(v) -> v
    Error(_) -> panic as "Expected stream_id and is_final in test_case payload"
  }
}

fn decode_event_type(payload: BitArray) -> String {
  let decoder = {
    use event_type <- decode.field("event", decode.string)
    decode.success(event_type)
  }
  case cbor.decode_bytes(payload, decoder) {
    Ok(v) -> v
    Error(_) -> panic as "Expected event in payload"
  }
}

fn decode_test_done_results(payload: BitArray) -> TestRunResult {
  let results_decoder = {
    use passed <- decode.field("passed", decode.bool)
    use total_count <- decode.field("test_cases", decode.int)
    use valid_count <- decode.field("valid_test_cases", decode.int)
    use invalid_count <- decode.field("invalid_test_cases", decode.int)
    use interesting_count <- decode.field("interesting_test_cases", decode.int)
    use seed <- decode.field("seed", decode.string)
    use flaky <- decode.optional_field(
      "flaky",
      option.None,
      decode.optional(decode.string),
    )
    use server_error <- decode.optional_field(
      "error",
      option.None,
      decode.optional(decode.string),
    )
    use health_check_failure <- decode.optional_field(
      "health_check_failure",
      option.None,
      decode.optional(decode.string),
    )
    decode.success(
      TestRunResult(
        passed:,
        valid_count:,
        total_count:,
        invalid_count:,
        interesting_count:,
        server_error:,
        flaky:,
        health_check_failure:,
        seed:,
        failure_message: None,
        failure_drawn_entries: [],
      ),
    )
  }

  let decoder = {
    use results <- decode.field("results", results_decoder)
    decode.success(results)
  }

  let assert Ok(v) = cbor.decode_bytes(payload, decoder)
  v
}

fn find_stream_by_monitor(
  in_flight: Dict(Int, process.Monitor),
  monitor: process.Monitor,
) -> Result(Int, Nil) {
  in_flight
  |> dict.to_list
  |> list.find(fn(entry) { entry.1 == monitor })
  |> case_result_map_first
}

fn case_result_map_first(r: Result(#(Int, process.Monitor), Nil)) {
  case r {
    Ok(#(stream_id, _)) -> Ok(stream_id)
    Error(_) -> Error(Nil)
  }
}

/// Mark one in-flight case as completed, applying the per-event bookkeeping
/// shared by Valid/Invalid/Interesting outcomes.
fn handle_case_done(
  state: RunState,
  stream_id: Int,
  message: Option(String),
  drawn_entries: List(recorder.DrawnEntry),
) -> RunState {
  let in_flight = case dict.get(state.in_flight, stream_id) {
    Ok(monitor) -> {
      process.demonitor_process(monitor)
      dict.delete(state.in_flight, stream_id)
    }
    Error(_) -> state.in_flight
  }

  let failure_message = case state.failure_message, message {
    Some(_), _ -> state.failure_message
    None, Some(_) -> message
    None, None -> None
  }

  let failure_drawn_entries = case state.failure_drawn_entries, drawn_entries {
    [], entries -> entries
    existing, _ -> existing
  }

  let replays_remaining = case state.test_done {
    Some(_) if state.replays_remaining > 0 -> state.replays_remaining - 1
    _ -> state.replays_remaining
  }

  RunState(
    ..state,
    in_flight:,
    failure_message:,
    failure_drawn_entries:,
    replays_remaining:,
  )
}

fn is_terminal(state: RunState) -> Bool {
  option.is_some(state.test_done)
  && dict.size(state.in_flight) == 0
  && state.replays_remaining == 0
}

fn handle_maybe_terminal(
  state: RunState,
  test_case_stream_id: Int,
  message: Option(String),
  drawn_entries: List(recorder.DrawnEntry),
) {
  let new_state =
    handle_case_done(state, test_case_stream_id, message, drawn_entries)

  case is_terminal(new_state) {
    True -> {
      let result = final_result(new_state)

      actor.send(state.reply_to, Ok(result))
      actor.stop()
    }
    False -> actor.continue(new_state)
  }
}

fn final_result(state: RunState) -> TestRunResult {
  let assert Some(test_result) = state.test_done
  TestRunResult(
    ..test_result,
    failure_message: option.or(
      test_result.failure_message,
      state.failure_message,
    ),
    failure_drawn_entries: case state.failure_drawn_entries {
      [] -> test_result.failure_drawn_entries
      entries -> entries
    },
  )
}

fn handle_message(
  state: RunState,
  message: RunMessage,
) -> actor.Next(RunState, RunMessage) {
  case message {
    S1Packet(packet) -> {
      let event_type = decode_event_type(packet.payload)
      case event_type {
        "test_case" -> {
          logging.log(logging.Debug, "[run] Received test_case event")
          let TestCaseEvent(stream_id: tc_stream_id, is_final:) =
            decode_test_case_event(packet.payload)

          // Ack S1 BEFORE spawning the worker, so the worker's S2 generate
          // cannot race ahead of the run-stream test_case_reply.
          session.send_reply_sync(
            state.session,
            state.test_stream.id,
            encode_reply(gbor.CBNull),
            packet.message_id,
          )

          let monitor =
            case_worker.spawn(
              state.session,
              tc_stream_id,
              state.test_fn,
              is_final,
              state.outcomes,
            )

          let new_state =
            RunState(
              ..state,
              in_flight: dict.insert(state.in_flight, tc_stream_id, monitor),
            )

          actor.continue(new_state)
        }
        "test_done" -> {
          logging.log(logging.Debug, "[run] Received test_done event")
          let results = decode_test_done_results(packet.payload)

          session.send_reply(
            state.session,
            state.test_stream.id,
            encode_reply(gbor.CBBool(True)),
            packet.message_id,
          )

          let new_state =
            RunState(
              ..state,
              test_done: Some(results),
              replays_remaining: results.interesting_count,
            )

          case is_terminal(new_state) {
            True -> {
              let result = final_result(new_state)

              actor.send(state.reply_to, Ok(result))
              actor.stop()
            }
            False -> actor.continue(new_state)
          }
        }
        other -> {
          logging.log(logging.Error, "[run] Unexpected event_type: " <> other)
          actor.send(
            state.reply_to,
            Error(InternalError(
              stream_id: Some(state.test_stream.id),
              reason: "unexpected event_type on run stream: " <> other,
            )),
          )
          actor.stop()
        }
      }
    }
    CaseOutcome(case_worker.Valid(stream_id)) -> {
      handle_maybe_terminal(state, stream_id, None, [])
    }
    CaseOutcome(case_worker.Invalid(stream_id)) -> {
      handle_maybe_terminal(state, stream_id, None, [])
    }
    CaseOutcome(case_worker.Overrun(stream_id)) -> {
      handle_maybe_terminal(state, stream_id, None, [])
    }
    CaseOutcome(case_worker.Interesting(stream_id, msg, drawn_entries)) -> {
      handle_maybe_terminal(state, stream_id, Some(msg), drawn_entries)
    }
    CaseOutcome(case_worker.InternalFailure(stream_id, reason)) -> {
      // Demonitor and drop the entry; we are aborting the run anyway.
      case dict.get(state.in_flight, stream_id) {
        Ok(monitor) -> process.demonitor_process(monitor)
        Error(_) -> Nil
      }
      actor.send(
        state.reply_to,
        Error(InternalError(stream_id: Some(stream_id), reason:)),
      )
      actor.stop()
    }
    CaseCrashed(down) -> {
      let stream_id = case down {
        ProcessDown(monitor:, ..) ->
          find_stream_by_monitor(state.in_flight, monitor)
        _ -> Error(Nil)
      }
      // Local cleanup: forget the dead owner. Do NOT attempt to send
      // mark_complete or stream_close; the case stream is in an unknown
      // protocol state on the server side, so we abort the whole run.
      case stream_id {
        Ok(sid) -> actor.send(state.session, session.UnregisterStreamOwner(sid))
        Error(_) -> Nil
      }
      actor.send(
        state.reply_to,
        Error(InternalError(
          stream_id: option.from_result(stream_id),
          reason: "case worker crashed: " <> string.inspect(down),
        )),
      )
      actor.stop()
    }
  }
}

fn format_drawn_entries(entries: List(recorder.DrawnEntry)) -> String {
  entries
  |> list.index_map(fn(entry, i) {
    "  Draw " <> int.to_string(i + 1) <> ": " <> entry.value
  })
  |> string.join("\n")
}

fn start(
  reply_to: process.Subject(Result(TestRunResult, InternalError)),
  session: process.Subject(session.SessionMessage),
  test_fn: fn(TestCase) -> Nil,
  test_cases: Int,
) -> Result(actor.Started(process.Subject(RunMessage)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject: process.Subject(RunMessage)) {
    let test_stream = session.open_stream(session)
    let run_test_payload =
      cbor.cbor_map([
        #("command", gbor.CBString("run_test")),
        #("stream_id", gbor.CBInt(test_stream.id)),
        #("test_cases", gbor.CBInt(test_cases)),
        #("seed", gbor.CBNull),
        #("database_key", gbor.CBNull),
        #("derandomize", gbor.CBBool(False)),
      ])

    let reply_packet =
      session.request_cbor(session, session.control_stream_id, run_test_payload)

    let run_test_reply_decoder = {
      use result <- decode.field("result", decode.bool)
      decode.success(result)
    }
    let reply = cbor.decode_bytes(reply_packet.payload, run_test_reply_decoder)

    case reply {
      Ok(True) -> Nil
      Ok(False) -> panic as "Server rejected run_test"
      Error(_) -> panic as "Could not decode run_test reply"
    }

    let outcomes: process.Subject(case_worker.Outcome) = process.new_subject()
    let selector = build_selector(test_stream, outcomes)

    let initial_state =
      RunState(
        outcomes:,
        test_fn:,
        reply_to:,
        session:,
        test_stream:,
        in_flight: dict.new(),
        failure_message: None,
        failure_drawn_entries: [],
        test_done: None,
        replays_remaining: 0,
      )

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn run_test(
  session_subject: process.Subject(session.SessionMessage),
  test_fn: fn(TestCase) -> Nil,
  test_cases: Int,
) -> Nil {
  let reply_subject = process.new_subject()

  // TODO: do not panic
  let assert Ok(_started) =
    start(reply_subject, session_subject, test_fn, test_cases)

  let result = process.receive(reply_subject, 60_000)

  case result {
    Error(_) -> panic as "Run actor timed out or crashed"
    Ok(Ok(run_result)) -> {
      // ... format and panic exactly like today's Ok(final_state) branch ...

      logging.log(
        logging.Debug,
        "[run] Test run complete, passed="
          <> case run_result.passed {
          True -> "true"
          False -> "false"
        },
      )

      // session.close_stream(session_subject, test_stream.id)

      case run_result.server_error {
        Some(msg) -> panic as { "Server error: " <> msg }
        None -> Nil
      }
      case run_result.health_check_failure {
        Some(msg) -> panic as { "Health check failure:\n" <> msg }
        None -> Nil
      }
      case run_result.flaky {
        Some(msg) -> panic as { "Flaky test detected: " <> msg }
        None -> Nil
      }

      case run_result.passed, run_result.failure_message {
        True, None -> Nil
        _, Some(message) -> {
          let draws_part = case run_result.failure_drawn_entries {
            [] -> ""
            entries -> "\n" <> format_drawn_entries(entries)
          }
          panic as {
            "Property test failed: "
            <> message
            <> draws_part
            <> "\n  seed: "
            <> run_result.seed
            <> "\n  ran "
            <> int.to_string(run_result.total_count)
            <> " test cases ("
            <> int.to_string(run_result.valid_count)
            <> " valid, "
            <> int.to_string(run_result.invalid_count)
            <> " invalid, "
            <> int.to_string(run_result.interesting_count)
            <> " shrunk)"
          }
        }
        False, None ->
          panic as {
            "Property test failed\n  seed: "
            <> run_result.seed
            <> "\n  ran "
            <> int.to_string(run_result.total_count)
            <> " test cases ("
            <> int.to_string(run_result.valid_count)
            <> " valid, "
            <> int.to_string(run_result.invalid_count)
            <> " invalid, "
            <> int.to_string(run_result.interesting_count)
            <> " shrunk)"
          }
      }
    }
    Ok(Error(InternalError(stream_id:, reason:))) -> {
      let stream_part = case stream_id {
        Some(sid) -> " (stream_id=" <> int.to_string(sid) <> ")"
        None -> ""
      }
      panic as { "Shelby internal failure: " <> reason <> stream_part }
    }
  }
}
