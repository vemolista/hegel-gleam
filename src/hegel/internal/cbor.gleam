import gbor
import gbor/decode as cbor_decode
import gbor/encode as cbor_encode
import gleam/dynamic/decode
import gleam/list

/// Build a CBOR map from string keys and CBOR values.
pub fn cbor_map(entries: List(#(String, gbor.CBOR))) -> gbor.CBOR {
  gbor.CBMap(
    entries
    |> list.map(fn(entry) { #(gbor.CBString(entry.0), entry.1) }),
  )
}

pub fn cbor_map_insert(
  map: gbor.CBOR,
  key: String,
  value: gbor.CBOR,
) -> gbor.CBOR {
  case map {
    gbor.CBMap(entries) -> {
      let key_cbor = gbor.CBString(key)
      let without_key = list.filter(entries, fn(e) { e.0 != key_cbor })
      gbor.CBMap(list.prepend(without_key, #(key_cbor, value)))
    }
    _ -> panic as "map insert called on a non-map element"
  }
}

/// Encode a CBOR value to bytes.
pub fn encode(value: gbor.CBOR) -> BitArray {
  let assert Ok(bytes) = cbor_encode.to_bit_array(value)
  bytes
}

/// Decode bytes into a Gleam value using a dynamic decoder.
pub fn decode_bytes(
  bytes: BitArray,
  decoder: decode.Decoder(a),
) -> Result(a, List(decode.DecodeError)) {
  let assert Ok(cbor) = cbor_decode.from_bit_array(bytes)
  let dynamic = cbor_decode.cbor_to_dynamic(cbor)
  decode.run(dynamic, decoder)
}
