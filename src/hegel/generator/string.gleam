// import gbor
// import gleam/bit_array
// import gleam/list
// import gleam/string
// import hegel/generator/generator.{type Generator}
// import hegel/internal/case_worker
// import hegel/internal/cbor

// pub fn new() -> Generator(String) {
//   generator.Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("string")),
//       // There is more you can do with the string schema, but let's wait for docs
//       #("exclude_categories", gbor.CBArray([gbor.CBString("Cs")])),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             result -> get_value(result)
//           }
//         other -> get_value(Ok(other))
//       }
//     },
//     display: fn(s) { "\"" <> s <> "\"" },
//   )
// }

// fn get_value(cbor: Result(gbor.CBOR, Nil)) -> String {
//   case cbor {
//     Ok(gbor.CBTagged(91, gbor.CBBinary(bit_array))) -> {
//       case bit_array.to_string(bit_array) {
//         Ok(v) -> v
//         Error(_) ->
//           case_worker.internal_panic(
//             "failed to parse bitarray to string, got: "
//             <> bit_array.inspect(bit_array),
//           )
//       }
//     }
//     _ ->
//       case_worker.internal_panic(
//         "expected CBOR tag 91, got: " <> string.inspect(cbor),
//       )
//   }
// }

// pub fn min_size(generator: Generator(String), min: Int) -> Generator(String) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "min_size", gbor.CBInt(min)),
//   )
// }

// pub fn max_size(generator: Generator(String), max: Int) -> Generator(String) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "max_size", gbor.CBInt(max)),
//   )
// }
