// import gbor
// import gbor/decode as cbor_decode
// import gleam/erlang/process
// import gleam/int
// import gleam/list
// import gleam/option
// import gleam/string
// import logging

// import hegel/internal/case_worker
// import hegel/internal/cbor
// import hegel/internal/recorder
// import hegel/internal/session
// import hegel/internal/test_case.{type TestCase}

// pub type Generator(a) {
//   Generator(
//     schema: gbor.CBOR,
//     parse: fn(gbor.CBOR) -> a,
//     display: fn(a) -> String,
//   )
// }

// pub fn draw(test_case: TestCase, generator: Generator(a)) -> a {
//   logging.log(
//     logging.Debug,
//     "[generator] Drawing value on stream_id="
//       <> int.to_string(test_case.stream_id),
//   )
//   let payload =
//     cbor.cbor_map([
//       #("command", gbor.CBString("generate")),
//       #("schema", generator.schema),
//     ])

//   logging.log(
//     logging.Debug,
//     "[generator] Sending generate request, schema="
//       <> string.inspect(generator.schema),
//   )

//   let reply_packet =
//     session.request_cbor(test_case.session, test_case.stream_id, payload)
//   logging.log(logging.Debug, "[generator] Received generated value")

//   let reply_cbor = case cbor_decode.from_bit_array(reply_packet.payload) {
//     Ok(c) -> c
//     Error(_) -> case_worker.internal_panic("could not decode generate reply")
//   }

//   logging.log(
//     logging.Debug,
//     "[generator] Raw reply_cbor: " <> string.inspect(reply_cbor),
//   )

//   let reply_cbor = case reply_cbor {
//     gbor.CBMap(entries) ->
//       case list.key_find(entries, gbor.CBString("error")) {
//         Ok(error_val) ->
//           case list.key_find(entries, gbor.CBString("type")) {
//             Ok(gbor.CBString("StopTest")) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server sent StopTest error, error_val="
//                   <> string.inspect(error_val),
//               )
//               case_worker.stop_test_panic()
//             }
//             Ok(gbor.CBString("FlakyStrategyDefinition")) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server sent FlakyStrategyDefinition error, error_val="
//                   <> string.inspect(error_val),
//               )
//               case_worker.stop_test_panic()
//             }
//             Ok(gbor.CBString("FlakyReplay")) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server sent FlakyReplay error, error_val="
//                   <> string.inspect(error_val),
//               )
//               case_worker.stop_test_panic()
//             }
//             Ok(gbor.CBString("UnsatisfiedAssumption")) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server sent UnsatisfiedAssumption error, error_val="
//                   <> string.inspect(error_val),
//               )
//               panic as "ASSUME_FAIL"
//             }
//             Ok(type_val) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server sent unknown error type: "
//                   <> string.inspect(type_val)
//                   <> ", error_val="
//                   <> string.inspect(error_val)
//                   <> ", full_entries="
//                   <> string.inspect(entries),
//               )
//               reply_cbor
//             }
//             Error(Nil) -> {
//               logging.log(
//                 logging.Debug,
//                 "[generator] Server error with no type key, error_val="
//                   <> string.inspect(error_val)
//                   <> ", full_entries="
//                   <> string.inspect(entries),
//               )
//               reply_cbor
//             }
//           }
//         _ -> reply_cbor
//       }
//     _ -> reply_cbor
//   }

//   logging.log(
//     logging.Debug,
//     "[generator] About to parse reply_cbor: " <> string.inspect(reply_cbor),
//   )

//   let parsed = generator.parse(reply_cbor)

//   case test_case.recorder {
//     option.Some(r) ->
//       process.send(r, recorder.Record(generator.display(parsed)))
//     option.None -> Nil
//   }

//   parsed
// }
