import gleam/erlang/process
import gleam/list
import gleam/otp/actor

pub type DrawnEntry {
  DrawnEntry(value: String)
}

pub type RecorderMessage {
  Record(value: String)
  Drain(reply: process.Subject(List(DrawnEntry)))
}

type RecorderState {
  RecorderState(entries: List(DrawnEntry))
}

pub fn start() -> process.Subject(RecorderMessage) {
  let assert Ok(started) =
    actor.new(RecorderState(entries: []))
    |> actor.on_message(fn(state, message) {
      case message {
        Record(value) ->
          actor.continue(
            RecorderState(
              entries: list.append(state.entries, [DrawnEntry(value:)]),
            ),
          )
        Drain(reply) -> {
          process.send(reply, state.entries)
          actor.continue(state)
        }
      }
    })
    |> actor.start()
  started.data
}
