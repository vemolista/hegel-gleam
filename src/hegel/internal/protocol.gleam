import gleam/bit_array
import gleam/int
import gzlib

// "HEGL" in big-endian
const packet_magic: Int = 0x4845474C

const packet_terminator: Int = 0x0A

fn reply_bit() -> Int {
  int.bitwise_shift_left(1, 31)
}

pub type Packet {
  Packet(stream_id: Int, message_id: Int, is_reply: Bool, payload: BitArray)
}

pub fn encode_packet(packet: Packet) -> BitArray {
  let message_id = case packet.is_reply {
    True -> int.bitwise_or(packet.message_id, reply_bit())
    False -> packet.message_id
  }

  let payload_size = bit_array.byte_size(packet.payload)

  let without_checksum = <<
    packet_magic:32,
    0:32,
    packet.stream_id:32,
    message_id:32,
    payload_size:32,
    packet.payload:bits,
  >>

  let checksum = case gzlib.crc32(without_checksum) {
    Ok(c) -> c
    Error(_) -> panic as "Packet must be bit aligned"
  }

  <<
    packet_magic:32,
    checksum:32,
    packet.stream_id:32,
    message_id:32,
    payload_size:32,
    packet.payload:bits,
    packet_terminator:8,
  >>
}

pub type DecodeError {
  NotEnoughData
  InvalidPacket(String)
}

pub fn decode_packet(
  data: BitArray,
) -> Result(#(Packet, BitArray), DecodeError) {
  case data {
    <<
      packet_magic_raw:32,
      checksum:32,
      stream_id:32,
      message_id_raw:32,
      payload_size:32,
      rest:bits,
    >> -> {
      let needed = payload_size + 1
      case bit_array.byte_size(rest) >= needed {
        False -> Error(NotEnoughData)
        True -> {
          let assert <<
            payload:bytes-size(payload_size),
            packet_terminator_raw:8,
            remaining:bits,
          >> = rest

          let without_checksum = <<
            packet_magic_raw:32,
            0:32,
            stream_id:32,
            message_id_raw:32,
            payload_size:32,
            payload:bits,
          >>

          let checksum_computed = case gzlib.crc32(without_checksum) {
            Ok(c) -> c
            Error(_) -> panic as "Data must be bit aligned"
          }

          case
            checksum == checksum_computed
            && packet_magic_raw == packet_magic
            && packet_terminator_raw == packet_terminator
          {
            False -> Error(InvalidPacket("checksum or magic mismatch"))
            True -> {
              let is_reply = int.bitwise_and(message_id_raw, reply_bit()) != 0
              let message_id =
                int.bitwise_and(message_id_raw, int.bitwise_not(reply_bit()))

              Ok(#(
                Packet(stream_id:, message_id:, is_reply:, payload:),
                remaining,
              ))
            }
          }
        }
      }
    }
    _ -> Error(NotEnoughData)
  }
}
