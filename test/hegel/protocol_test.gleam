import gleam/bit_array
import hegel/internal/protocol

pub fn encode_sanity_test() {
  let packet =
    protocol.Packet(
      stream_id: 1,
      message_id: 42,
      is_reply: False,
      payload: bit_array.from_string("hello"),
    )

  let _result = protocol.encode_packet(packet)
}

pub fn encode_decode_roundtrip_test() {
  let packet =
    protocol.Packet(
      stream_id: 1,
      message_id: 42,
      is_reply: True,
      payload: bit_array.from_string("hello"),
    )

  let assert Ok(#(decoded, <<>>)) =
    protocol.decode_packet(protocol.encode_packet(packet))
  assert packet == decoded
}
