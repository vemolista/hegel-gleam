// import gbor
// import gleam/int
// import gleam/list
// import gleam/string
// import hegel/generator/generator.{type Generator, Generator}
// import hegel/internal/case_worker
// import hegel/internal/cbor

// fn parse_elem(gen: Generator(a), elem: gbor.CBOR) -> a {
//   gen.parse(gbor.CBMap([#(gbor.CBString("result"), elem)]))
// }

// fn display2(a: Generator(a), b: Generator(b), tuple: #(a, b)) -> String {
//   let a_str = a.display(tuple.0)
//   let b_str = b.display(tuple.1)
//   "#(" <> a_str <> ", " <> b_str <> ")"
// }

// fn display3(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
//   tuple: #(a, b, c),
// ) -> String {
//   let a_str = a.display(tuple.0)
//   let b_str = b.display(tuple.1)
//   let c_str = c.display(tuple.2)
//   "#(" <> a_str <> ", " <> b_str <> ", " <> c_str <> ")"
// }

// fn display4(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
//   d: Generator(dd),
//   tuple: #(a, b, c, dd),
// ) -> String {
//   let a_str = a.display(tuple.0)
//   let b_str = b.display(tuple.1)
//   let c_str = c.display(tuple.2)
//   let d_str = d.display(tuple.3)
//   "#(" <> a_str <> ", " <> b_str <> ", " <> c_str <> ", " <> d_str <> ")"
// }

// fn display5(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
//   d: Generator(dd),
//   e: Generator(ee),
//   tuple: #(a, b, c, dd, ee),
// ) -> String {
//   let a_str = a.display(tuple.0)
//   let b_str = b.display(tuple.1)
//   let c_str = c.display(tuple.2)
//   let d_str = d.display(tuple.3)
//   let e_str = e.display(tuple.4)
//   "#("
//   <> a_str
//   <> ", "
//   <> b_str
//   <> ", "
//   <> c_str
//   <> ", "
//   <> d_str
//   <> ", "
//   <> e_str
//   <> ")"
// }

// pub fn new2(a: Generator(a), b: Generator(b)) -> Generator(#(a, b)) {
//   Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("tuple")),
//       #("elements", gbor.CBArray([a.schema, b.schema])),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray([val_a, val_b])) -> #(
//               parse_elem(a, val_a),
//               parse_elem(b, val_b),
//             )
//             Ok(gbor.CBArray(other)) ->
//               case_worker.internal_panic(
//                 "expected tuple of 2 elements, got: "
//                 <> int.to_string(list.length(other)),
//               )
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
//     display: fn(tuple) { display2(a, b, tuple) },
//   )
// }

// pub fn new3(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
// ) -> Generator(#(a, b, c)) {
//   Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("tuple")),
//       #("elements", gbor.CBArray([a.schema, b.schema, c.schema])),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray([val_a, val_b, val_c])) -> #(
//               parse_elem(a, val_a),
//               parse_elem(b, val_b),
//               parse_elem(c, val_c),
//             )
//             Ok(gbor.CBArray(other)) ->
//               case_worker.internal_panic(
//                 "expected tuple of 3 elements, got: "
//                 <> int.to_string(list.length(other)),
//               )
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
//     display: fn(tuple) { display3(a, b, c, tuple) },
//   )
// }

// pub fn new4(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
//   d: Generator(dd),
// ) -> Generator(#(a, b, c, dd)) {
//   Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("tuple")),
//       #("elements", gbor.CBArray([a.schema, b.schema, c.schema, d.schema])),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray([val_a, val_b, val_c, val_d])) -> #(
//               parse_elem(a, val_a),
//               parse_elem(b, val_b),
//               parse_elem(c, val_c),
//               parse_elem(d, val_d),
//             )
//             Ok(gbor.CBArray(other)) ->
//               case_worker.internal_panic(
//                 "expected tuple of 4 elements, got: "
//                 <> int.to_string(list.length(other)),
//               )
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
//     display: fn(tuple) { display4(a, b, c, d, tuple) },
//   )
// }

// pub fn new5(
//   a: Generator(a),
//   b: Generator(b),
//   c: Generator(c),
//   d: Generator(dd),
//   e: Generator(ee),
// ) -> Generator(#(a, b, c, dd, ee)) {
//   Generator(
//     schema: cbor.cbor_map([
//       #("type", gbor.CBString("tuple")),
//       #(
//         "elements",
//         gbor.CBArray([a.schema, b.schema, c.schema, d.schema, e.schema]),
//       ),
//     ]),
//     parse: fn(cbor: gbor.CBOR) {
//       case cbor {
//         gbor.CBMap(entries) ->
//           case list.key_find(entries, gbor.CBString("result")) {
//             Ok(gbor.CBArray([val_a, val_b, val_c, val_d, val_e])) -> #(
//               parse_elem(a, val_a),
//               parse_elem(b, val_b),
//               parse_elem(c, val_c),
//               parse_elem(d, val_d),
//               parse_elem(e, val_e),
//             )
//             Ok(gbor.CBArray(other)) ->
//               case_worker.internal_panic(
//                 "expected tuple of 5 elements, got: "
//                 <> int.to_string(list.length(other)),
//               )
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
//     display: fn(tuple) { display5(a, b, c, d, e, tuple) },
//   )
// }
