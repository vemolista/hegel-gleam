import gbor
import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/port.{type Port}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/otp/actor
import gleam/result
import gleam/string
import hegel/internal/cbor
import hegel/internal/protocol
import logging

const hegel_version: String = "0.6.1"

const supported_protocol_version: String = "0.12"

pub const control_stream_id: Int = 0

const stream_close_byte = <<0xFE>>

type HegelServerInstance =
  Port

pub type SessionState {
  SessionState(
    port: HegelServerInstance,
    read_buffer: BitArray,
    handshake_complete: Bool,
    protocol_version: String,
    next_client_stream_id: Int,
    next_message_id: Dict(Int, Int),
    stream_owners: Dict(Int, process.Subject(protocol.Packet)),
    pending_replies: Dict(#(Int, Int), process.Subject(protocol.Packet)),
  )
}

pub type Stream {
  Stream(id: Int, subject: process.Subject(protocol.Packet))
}

pub type SessionMessage {
  PortData(BitArray)
  PortExit(Int)
  PortDown(reason: process.ExitReason)
  PortUnexpected(dynamic.Dynamic)

  Request(stream_id: Int, payload: BitArray, reply: Subject(protocol.Packet))
  Reply(stream_id: Int, payload: BitArray, in_reply_to: Int)
  ReplySync(
    stream_id: Int,
    payload: BitArray,
    in_reply_to: Int,
    ack: Subject(Nil),
  )
  Receive(stream_id: Int, reply: Subject(protocol.Packet))

  RegisterStreamOwner(stream_id: Int, subject: Subject(protocol.Packet))
  UnregisterStreamOwner(stream_id: Int)
  OpenClientStream(owner: Subject(protocol.Packet), reply: Subject(Int))
  CloseStream(stream_id: Int)
}

// --- TRANSPORT ---

/// Client-initiated stream
pub fn open_stream(session: Subject(SessionMessage)) -> Stream {
  let subject = process.new_subject()
  let stream_id = process.call(session, 5000, OpenClientStream(subject, _))

  Stream(stream_id, subject)
}

/// Server-initiated stream
pub fn register_stream(
  session: Subject(SessionMessage),
  stream_id: Int,
) -> Stream {
  let subject = process.new_subject()
  process.send(session, RegisterStreamOwner(stream_id:, subject:))

  Stream(id: stream_id, subject:)
}

pub fn close_stream(session: Subject(SessionMessage), stream_id: Int) -> Nil {
  process.send(session, CloseStream(stream_id:))
}

/// A synchronous message to the server on a given stream
pub fn request(
  session: Subject(SessionMessage),
  stream_id: Int,
  payload: BitArray,
) -> protocol.Packet {
  process.call_forever(session, Request(stream_id, payload, _))
}

pub fn send_reply(
  session: Subject(SessionMessage),
  stream_id: Int,
  payload: BitArray,
  message_id in_reply_to: Int,
) -> Nil {
  process.send(session, Reply(stream_id:, payload:, in_reply_to:))
}

pub fn send_reply_sync(
  session: Subject(SessionMessage),
  stream_id: Int,
  payload: BitArray,
  message_id in_reply_to: Int,
) -> Nil {
  process.call(session, 5000, fn(ack) {
    ReplySync(stream_id:, payload:, in_reply_to:, ack:)
  })
}

pub fn request_cbor(
  session: Subject(SessionMessage),
  stream_id: Int,
  data: gbor.CBOR,
) {
  let payload = cbor.encode(data)
  request(session, stream_id, payload)
}

@external(erlang, "hegel_ffi", "port_send")
fn port_send(port: Port, data: BitArray) -> Nil

@external(erlang, "hegel_ffi", "port_connect")
fn port_connect(port: Port, pid: process.Pid) -> Nil

@external(erlang, "hegel_ffi", "receive_port_data")
fn receive_port_data(port: Port) -> Result(BitArray, Nil)

fn handle_message(
  state: SessionState,
  message: SessionMessage,
) -> actor.Next(SessionState, SessionMessage) {
  case message {
    PortData(bytes) -> {
      let state =
        SessionState(
          ..state,
          read_buffer: bit_array.append(state.read_buffer, bytes),
        )
      let state = drain(state)
      actor.continue(state)
    }
    Request(stream_id, payload, reply) -> {
      let message_id = case dict.get(state.next_message_id, stream_id) {
        Ok(v) -> v
        // TODO - no panic
        Error(_) -> panic
      }

      let packet =
        protocol.Packet(stream_id:, message_id:, is_reply: False, payload:)
      port_send(state.port, protocol.encode_packet(packet))

      let state =
        SessionState(
          ..state,
          next_message_id: dict.insert(
            state.next_message_id,
            stream_id,
            message_id + 1,
          ),
          pending_replies: dict.insert(
            state.pending_replies,
            #(stream_id, message_id),
            reply,
          ),
        )

      actor.continue(state)
    }
    CloseStream(stream_id) -> {
      let message_id = int.bitwise_shift_left(1, 31) - 1
      let packet =
        protocol.Packet(
          stream_id:,
          message_id:,
          is_reply: False,
          payload: stream_close_byte,
        )
      let payload = protocol.encode_packet(packet)

      port_send(state.port, payload)

      let state =
        SessionState(
          ..state,
          stream_owners: dict.delete(state.stream_owners, stream_id),
          next_message_id: dict.delete(state.next_message_id, stream_id),
        )

      actor.continue(state)
    }
    Reply(stream_id, payload, in_reply_to) -> {
      let packet =
        protocol.Packet(
          stream_id:,
          message_id: in_reply_to,
          is_reply: True,
          payload:,
        )

      port_send(state.port, protocol.encode_packet(packet))
      actor.continue(state)
    }
    ReplySync(stream_id, payload, in_reply_to, ack) -> {
      let packet =
        protocol.Packet(
          stream_id:,
          message_id: in_reply_to,
          is_reply: True,
          payload:,
        )

      port_send(state.port, protocol.encode_packet(packet))
      process.send(ack, Nil)
      actor.continue(state)
    }
    RegisterStreamOwner(stream_id, subject) -> {
      // Seed the per-stream client-side message-id counter so case
      // workers can send `generate` / `mark_complete` on
      // server-created streams.
      let next_message_id = case dict.get(state.next_message_id, stream_id) {
        Ok(_) -> state.next_message_id
        Error(_) -> dict.insert(state.next_message_id, stream_id, 1)
      }
      actor.continue(
        SessionState(
          ..state,
          stream_owners: dict.insert(state.stream_owners, stream_id, subject),
          next_message_id:,
        ),
      )
    }
    UnregisterStreamOwner(stream_id) -> {
      actor.continue(
        SessionState(
          ..state,
          stream_owners: dict.delete(state.stream_owners, stream_id),
          next_message_id: dict.delete(state.next_message_id, stream_id),
        ),
      )
    }
    OpenClientStream(owner, reply) -> {
      let stream_id = state.next_client_stream_id
      process.send(reply, stream_id)
      actor.continue(
        SessionState(
          ..state,
          next_client_stream_id: state.next_client_stream_id + 2,
          stream_owners: dict.insert(state.stream_owners, stream_id, owner),
          next_message_id: dict.insert(state.next_message_id, stream_id, 1),
        ),
      )
    }
    Receive(_, _) -> actor.continue(state)
    PortExit(_) -> actor.continue(state)
    PortDown(_) -> actor.continue(state)
    PortUnexpected(_) -> actor.continue(state)
  }
}

fn drain(state: SessionState) -> SessionState {
  case protocol.decode_packet(state.read_buffer) {
    // Base case - Not enough bytes to decode
    Error(_) -> state
    // Recursive case - decode packets until out of buffer
    Ok(#(packet, remaining)) -> {
      let key = #(packet.stream_id, packet.message_id)
      let state = case packet.is_reply, dict.get(state.pending_replies, key) {
        // Reply from server, send to who's waiting for it
        True, Ok(reply_subject) -> {
          process.send(reply_subject, packet)
          SessionState(
            ..state,
            pending_replies: dict.delete(state.pending_replies, key),
          )
        }
        // Reply with no one waiting for it - "orphaned"
        True, Error(_) -> {
          logging.log(
            logging.Debug,
            "Reply packet received without a correspoding pending reply"
              <> int.to_string(packet.stream_id)
              <> " message_id: "
              <> int.to_string(packet.message_id)
              <> " is_reply: "
              <> bool.to_string(packet.is_reply),
          )
          state
        }
        // Server pushed packet
        False, _ ->
          case dict.get(state.stream_owners, packet.stream_id) {
            Ok(owner) -> {
              process.send(owner, packet)
              state
            }
            Error(_) -> {
              logging.log(
                logging.Debug,
                "Packet for unregistered stream received. stream_id: "
                  <> int.to_string(packet.stream_id)
                  <> " message_id: "
                  <> int.to_string(packet.message_id)
                  <> " is_reply: "
                  <> bool.to_string(packet.is_reply),
              )
              state
            }
          }
      }
      drain(SessionState(..state, read_buffer: remaining))
    }
  }
}

// --- LIFECYCLE ---

const handshake_reply_prefix: String = "Hegel/"

const handshake_payload: String = "hegel_handshake_start"

@external(erlang, "hegel_ffi", "open_port")
fn open_port(command: String, args: List(String)) -> Port

@external(erlang, "hegel_ffi", "find_executable")
fn find_executable(name: String) -> Result(String, Nil)

fn find_uv() -> Result(String, String) {
  find_executable("uv")
  |> result.replace_error(
    "uv not found on PATH. Install uv: https://docs.astral.sh/uv/",
  )
}

pub fn start(
  actor_name: process.Name(SessionMessage),
) -> Result(actor.Started(Subject(SessionMessage)), actor.StartError) {
  // TODO: Handle error gracefully
  let assert Ok(uv_path) = find_uv()

  let port =
    open_port(uv_path, [
      "tool",
      "run",
      "--from",
      "hegel-core==" <> hegel_version,
      "hegel",
      "--verbosity",
      "normal",
    ])

  let handshake_request =
    protocol.encode_packet(protocol.Packet(
      stream_id: control_stream_id,
      message_id: 0,
      is_reply: False,
      payload: bit_array.from_string(handshake_payload),
    ))

  port_send(port, handshake_request)
  let assert Ok(#(handshake_reply, _)) =
    receive_port_data(port)
    |> result.map_error(fn(_) { protocol.InvalidPacket("") })
    |> result.try(protocol.decode_packet)

  let handshake_reply_payload = case
    bit_array.to_string(handshake_reply.payload)
  {
    Ok(v) -> v
    Error(_) -> panic as "Failed to decode handshake reply payload"
  }

  let assert Ok(protocol_version) = case
    string.starts_with(handshake_reply_payload, handshake_reply_prefix)
  {
    True ->
      Ok(string.drop_start(
        handshake_reply_payload,
        string.length(handshake_reply_prefix),
      ))
    // TODO: Improve panic message
    False -> panic as "Bad handshake response"
  }

  // TODO: Accept compatible protocol versions instead of crashing if
  // we do not get this specific version. See hegel-rust/src/runner.rs:SUPPORTED_PROTOCOL_VERSIONS
  let assert True = supported_protocol_version == protocol_version

  let initial_state =
    SessionState(
      port:,
      read_buffer: <<>>,
      handshake_complete: True,
      protocol_version: supported_protocol_version,
      next_client_stream_id: 3,
      // Message Id 0 was sent in the handshake, so start at 1
      next_message_id: dict.from_list([#(control_stream_id, 1)]),
      stream_owners: dict.new(),
      pending_replies: dict.new(),
    )

  actor.new_with_initialiser(1000, fn(subject: Subject(SessionMessage)) {
    // The port is owned by the process that has opened it.
    // In this case, it was the application startup. However,
    // we want the port to be owned by this actor, so connect
    // to it here.
    port_connect(port, process.self())

    let selector =
      process.new_selector()
      |> process.select_record(port, 1, map_port_message)
      |> process.select(subject)

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.named(actor_name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

/// Map a raw message from the port to a message the actor can handle
fn map_port_message(message: dynamic.Dynamic) -> SessionMessage {
  // Port messages arrive as {Port, {data, Data}} or {Port, {exit_status, int}}
  // select_record passes the WHOLE tuple to this function.
  // We decode at [1, 1] to get the Data from {Port, {data, Data}}
  case decode.run(message, decode.at([1, 1], decode.bit_array)) {
    Ok(data) -> PortData(data)
    Error(_) -> handle_non_port_data_message(message)
  }
}

/// Handle a message from the port that is not a data message.
/// Right now we are handling exit_code messages, which tell us that the port
/// has exited or failed to properly start.
/// Port messages arrive as {Port, {exit_status, int}} - we need to decode at [1]
fn handle_non_port_data_message(message: dynamic.Dynamic) -> SessionMessage {
  // Decode the inner tuple at index 1: {exit_status, int}
  let inner_decoder = {
    use atom_val <- decode.field(0, atom.decoder())
    use int_val <- decode.field(1, decode.int)
    decode.success(#(atom_val, int_val))
  }
  let tuple_decoder = decode.at([1], inner_decoder)
  case decode.run(message, tuple_decoder) {
    Ok(#(atom_exit_status, exit_status)) -> {
      case atom_exit_status == atom.create("exit_status") {
        True -> PortExit(exit_status)
        False -> PortUnexpected(message)
      }
    }
    Error(_) -> PortUnexpected(message)
  }
}
