// import gbor
// import gleam/dynamic/decode
// import hegel/internal/cbor

// pub fn cbor_map_roundtrip_test() {
//   let value =
//     cbor.cbor_map([
//       #("command", gbor.CBString("generate")),
//       #(
//         "schema",
//         cbor.cbor_map([
//           #("type", gbor.CBString("integer")),
//           #("min_value", gbor.CBInt(0)),
//           #("max_value", gbor.CBInt(100)),
//         ]),
//       ),
//     ])

//   let bytes = cbor.encode(value)

//   let command_decoder = {
//     use command <- decode.field("command", decode.string)
//     decode.success(command)
//   }

//   let assert Ok("generate") = cbor.decode_bytes(bytes, command_decoder)
// }

// pub fn decode_server_response_test() {
//   // Simulating a server response: {"result": 42}
//   let response = cbor.cbor_map([#("result", gbor.CBInt(42))])
//   let bytes = cbor.encode(response)

//   let result_decoder = {
//     use result <- decode.field("result", decode.int)
//     decode.success(result)
//   }

//   let assert Ok(42) = cbor.decode_bytes(bytes, result_decoder)
// }

// pub fn decode_bool_response_test() {
//   // Simulating run_test reply: {"result": true}
//   let response = cbor.cbor_map([#("result", gbor.CBBool(True))])
//   let bytes = cbor.encode(response)

//   let result_decoder = {
//     use result <- decode.field("result", decode.bool)
//     decode.success(result)
//   }

//   let assert Ok(True) = cbor.decode_bytes(bytes, result_decoder)
// }

// pub fn decode_nested_map_test() {
//   // Simulating: {"command": "run_test", "stream_id": 3, "test_cases": 100}
//   let value =
//     cbor.cbor_map([
//       #("command", gbor.CBString("run_test")),
//       #("stream_id", gbor.CBInt(3)),
//       #("test_cases", gbor.CBInt(100)),
//     ])
//   let bytes = cbor.encode(value)

//   let decoder = {
//     use command <- decode.field("command", decode.string)
//     use stream_id <- decode.field("stream_id", decode.int)
//     use test_cases <- decode.field("test_cases", decode.int)
//     decode.success(#(command, stream_id, test_cases))
//   }

//   let assert Ok(#("run_test", 3, 100)) = cbor.decode_bytes(bytes, decoder)
// }
