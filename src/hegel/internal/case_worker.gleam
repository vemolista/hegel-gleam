import exception.{type Exception, Errored, Exited, Thrown}
import gbor
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/option
import gleam/string
import hegel/internal/cbor
import hegel/internal/recorder
import hegel/internal/session
import hegel/internal/test_case.{type TestCase, TestCase}
import logging

pub type Outcome {
  Valid(stream_id: Int)
  Invalid(stream_id: Int)
  Interesting(
    stream_id: Int,
    message: String,
    drawn_entries: List(recorder.DrawnEntry),
  )
  /// Backend-initiated data exhaustion (StopTest / flaky abort).
  /// mark_complete is intentionally skipped for this outcome.
  Overrun(stream_id: Int)
  // Reserved for cases where the worker decides a transport/protocol
  // problem is not the user's fault. Crash-derived internal failures
  // come from the run worker's monitor path, not from this variant.
  InternalFailure(stream_id: Int, reason: String)
}

const assume_sentinel = "ASSUME_FAIL"

const stop_test_sentinel = "__SHELBY_STOP_TEST"

const internal_prefix = "__SHELBY_INTERNAL: "

pub fn internal_panic(message: String) -> a {
  panic as { internal_prefix <> message }
}

pub fn stop_test_panic() -> a {
  panic as stop_test_sentinel
}

pub fn extract_panic_message(exc: Exception) -> String {
  let dyn = case exc {
    Errored(d) -> d
    Thrown(d) -> d
    Exited(d) -> d
  }

  // Gleam panics produce an Erlang map with atom keys, so we need to use
  // an actual atom to index into the map (string keys won't match)
  let message_key = atom.create("message")
  let message_decoder = {
    use msg <- decode.field(message_key, decode.string)
    decode.success(msg)
  }

  case decode.run(dyn, message_decoder) {
    Ok(msg) -> msg
    Error(_) ->
      case decode.run(dyn, decode.string) {
        Ok(msg) -> msg
        Error(_) -> string.inspect(dyn)
      }
  }
}

/// Spawn a case worker as an unlinked process and return a monitor for it.
///
/// The worker is unlinked so that any crash outside the worker's own
/// `exception.rescue` does not propagate to the run worker. The monitor
/// allows the run worker to observe such crashes and treat them as a fatal
/// internal failure.
pub fn spawn(
  session: process.Subject(session.SessionMessage),
  stream_id: Int,
  test_fn: fn(TestCase) -> Nil,
  is_final: Bool,
  reply_to: process.Subject(Outcome),
) -> process.Monitor {
  let pid =
    process.spawn_unlinked(fn() {
      run(session, stream_id, test_fn, is_final, reply_to)
    })
  process.monitor(pid)
}

fn run(
  session: process.Subject(session.SessionMessage),
  stream_id: Int,
  test_fn: fn(TestCase) -> Nil,
  is_final: Bool,
  reply_to: process.Subject(Outcome),
) -> Nil {
  logging.log(
    logging.Debug,
    "[case_worker] Running test case stream_id="
      <> int.to_string(stream_id)
      <> ", is_final="
      <> case is_final {
      True -> "true"
      False -> "false"
    },
  )

  let _stream = session.register_stream(session, stream_id)

  let recorder_subject = case is_final {
    True -> option.Some(recorder.start())
    False -> option.None
  }

  let tc = TestCase(session:, stream_id:, is_final:, recorder: recorder_subject)
  let result = exception.rescue(fn() { test_fn(tc) })

  let drawn_entries = case recorder_subject {
    option.Some(r) -> {
      let reply_subject = process.new_subject()
      process.send(r, recorder.Drain(reply_subject))
      let assert Ok(entries) = process.receive(reply_subject, 5000)
      entries
    }
    option.None -> []
  }

  case result {
    Ok(_) -> {
      logging.log(
        logging.Debug,
        "[case_worker] stream_id=" <> int.to_string(stream_id),
      )
      send_mark_complete(session, stream_id, "VALID", gbor.CBNull)
      process.send(reply_to, Valid(stream_id))
      session.close_stream(session, stream_id)
    }
    Error(exception) -> {
      let msg = extract_panic_message(exception)
      logging.log(
        logging.Debug,
        "[case_worker] stream_id="
          <> int.to_string(stream_id)
          <> " FAILED msg="
          <> msg,
      )
      case string.starts_with(msg, internal_prefix) {
        True -> {
          process.send(reply_to, InternalFailure(stream_id, msg))
        }
        False ->
          case msg == assume_sentinel {
            True -> {
              send_mark_complete(session, stream_id, "INVALID", gbor.CBNull)
              process.send(reply_to, Invalid(stream_id))
              session.close_stream(session, stream_id)
            }
            False ->
              case msg == stop_test_sentinel {
                True -> {
                  logging.log(
                    logging.Debug,
                    "[case_worker] stream_id="
                      <> int.to_string(stream_id)
                      <> " hit StopTest",
                  )
                  process.send(reply_to, Overrun(stream_id))
                  session.close_stream(session, stream_id)
                }
                False -> {
                  send_mark_complete(
                    session,
                    stream_id,
                    "INTERESTING",
                    gbor.CBString("Panic: " <> msg),
                  )
                  process.send(
                    reply_to,
                    Interesting(stream_id, msg, drawn_entries),
                  )
                  session.close_stream(session, stream_id)
                }
              }
          }
      }
    }
  }

  Nil
}

fn send_mark_complete(
  session: process.Subject(session.SessionMessage),
  stream_id: Int,
  status: String,
  origin: gbor.CBOR,
) -> Nil {
  let payload =
    cbor.cbor_map([
      #("command", gbor.CBString("mark_complete")),
      #("status", gbor.CBString(status)),
      #("origin", origin),
    ])
  let _reply = session.request_cbor(session, stream_id, payload)
  Nil
}
