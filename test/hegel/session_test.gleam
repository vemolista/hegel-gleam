import gleam/erlang/process
import hegel/internal/session

pub fn start_session_and_handshake_test() {
  let name = process.new_name("session_test")
  let assert Ok(_session) = session.start(name)
}
