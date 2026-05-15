import gbor
import gbor/decode as cbor_decode
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, Some}
import hegel/internal/case_worker
import hegel/internal/cbor
import hegel/internal/recorder
import hegel/internal/session
import hegel/internal/test_case.{type TestCase}

pub type BasicGenerator(a) {
  BasicGenerator(
    schema: gbor.CBOR,
    parse_raw: fn(gbor.CBOR) -> a,
    display: fn(a) -> String,
  )
}

pub opaque type Generator(a) {
  Generator(
    draw: fn(TestCase) -> a,
    as_basic: Option(BasicGenerator(a)),
    display: fn(a) -> String,
  )
}

pub fn from_basic(basic: BasicGenerator(a)) -> Generator(a) {
  Generator(
    draw: fn(tc) { draw_basic(tc, basic) },
    as_basic: Some(basic),
    display: basic.display,
  )
}

pub fn draw(test_case: TestCase, generator: Generator(a)) -> a {
  generator.draw(test_case)
}

pub fn as_basic(generator: Generator(a)) -> Option(BasicGenerator(a)) {
  generator.as_basic
}

pub fn draw_basic(test_case: TestCase, generator: BasicGenerator(a)) -> a {
  let payload =
    cbor.cbor_map([
      #("command", gbor.CBString("generate")),
      #("schema", generator.schema),
    ])

  let reply_packet =
    session.request_cbor(test_case.session, test_case.stream_id, payload)

  let reply_cbor = case cbor_decode.from_bit_array(reply_packet.payload) {
    Ok(c) -> c
    Error(_) -> case_worker.internal_panic("could not decode generate reply")
  }

  let reply_cbor = case reply_cbor {
    gbor.CBMap(entries) ->
      case list.key_find(entries, gbor.CBString("error")) {
        Ok(_) ->
          case list.key_find(entries, gbor.CBString("type")) {
            Ok(gbor.CBString("StopTest")) -> {
              case_worker.stop_test_panic()
            }
            Ok(gbor.CBString("FlakyStrategyDefinition")) -> {
              case_worker.stop_test_panic()
            }
            Ok(gbor.CBString("FlakyReplay")) -> {
              case_worker.stop_test_panic()
            }
            Ok(gbor.CBString("UnsatisfiedAssumption")) -> {
              panic as "ASSUME_FAIL"
            }
            Ok(_) -> {
              reply_cbor
            }
            Error(Nil) -> {
              reply_cbor
            }
          }
        _ -> reply_cbor
      }
    _ -> reply_cbor
  }

  let value_cbor = case reply_cbor {
    gbor.CBMap(entries) -> {
      case list.key_find(entries, gbor.CBString("result")) {
        Ok(v) -> v
        Error(_) -> panic as "expected a result key"
      }
    }
    _ -> panic as "expected a gbor map"
  }

  let parsed = generator.parse_raw(value_cbor)

  case test_case.recorder {
    option.Some(r) ->
      process.send(r, recorder.Record(generator.display(parsed)))
    option.None -> Nil
  }

  parsed
}
