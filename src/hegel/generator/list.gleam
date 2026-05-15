// import gbor
// import gleam/int
// import gleam/list
// import gleam/string
// import logging
// import hegel/generator/generator
// import hegel/internal/case_worker
// import hegel/internal/cbor

// pub fn new(generator: generator.Generator(a)) -> generator.Generator(List(a)) {
//   generator.Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("list")),
//       #("elements", generator.schema),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       logging.log(
//         logging.Debug,
//         "[list] Parsing CBOR: " <> string.inspect(cbor),
//       )
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray(value)) -> {
//               let parsed =
//                 list.map(value, fn(elem) {
//                   generator.parse(
//                     gbor.CBMap([#(gbor.CBString("result"), elem)]),
//                   )
//                 })
//               logging.log(
//                 logging.Debug,
//                 "[list] Parsed list of length: "
//                   <> int.to_string(list.length(parsed)),
//               )
//               parsed
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
//         other ->
//           case_worker.internal_panic(
//             "expected map, got: " <> string.inspect(other),
//           )
//       }
//     },
//     display: fn(items) {
//       let formatted = list.map(items, generator.display)
//       "[" <> string.join(formatted, ", ") <> "]"
//     },
//   )
// }

// pub fn min_size(
//   generator: generator.Generator(List(a)),
//   min: Int,
// ) -> generator.Generator(List(a)) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "min_size", gbor.CBInt(min)),
//   )
// }

// pub fn max_size(
//   generator: generator.Generator(List(a)),
//   max: Int,
// ) -> generator.Generator(List(a)) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "max_size", gbor.CBInt(max)),
//   )
// }

// pub fn unique(
//   generator: generator.Generator(List(a)),
// ) -> generator.Generator(List(a)) {
//   generator.Generator(
//     ..generator,
//     schema: cbor.cbor_map_insert(generator.schema, "unique", gbor.CBBool(True)),
//   )
// }
