import gleam/erlang/process
import gleam/option.{type Option}
import hegel/internal/recorder
import hegel/internal/session

pub type TestCase {
  TestCase(
    session: process.Subject(session.SessionMessage),
    stream_id: Int,
    is_final: Bool,
    recorder: Option(process.Subject(recorder.RecorderMessage)),
  )
}
