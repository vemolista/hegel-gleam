// import gbor
// import gleam/dict.{type Dict}
// import gleam/list
// import gleam/string
// import hegel/generator/generator
// import hegel/internal/case_worker
// import hegel/internal/cbor

// pub fn new(
//   keys: generator.Generator(a),
//   values: generator.Generator(b),
// ) -> generator.Generator(Dict(a, b)) {
//   generator.Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("dict")),
//       #("keys", keys.schema),
//       #("values", values.schema),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) -> {
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray(pairs)) -> {
//               list.map(pairs, fn(pair) {
//                 case pair {
//                   gbor.CBArray([key, value]) -> #(
//                     keys.parse(key),
//                     values.parse(value),
//                   )

//                   other ->
//                     case_worker.internal_panic(
//                       "expected elements to be pairs, got: "
//                       <> string.inspect(other),
//                     )
//                 }
//               })
//               |> dict.from_list
//             }
//             Ok(other) ->
//               case_worker.internal_panic(
//                 "expected result key with array value, got: "
//                 <> string.inspect(other),
//               )
//             Error(Nil) ->
//               case_worker.internal_panic(
//                 "result key not found in map, got: " <> string.inspect(cbor),
//               )
//           }
//         }

//         other ->
//           case_worker.internal_panic(
//             "expected map, got: " <> string.inspect(other),
//           )
//       }
//     },
//     // TODO: Do something smarter for displaying dicts
//     display: fn(dict) { string.inspect(dict) },
//   )
// }

// pub fn min_size(generator: generator.Generator(Dict(a, b)), min: Int) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "min_size", gbor.CBInt(min)),
//   )
// }

// pub fn max_size(generator: generator.Generator(Dict(a, b)), max: Int) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "max_size", gbor.CBInt(max)),
//   )
// }
