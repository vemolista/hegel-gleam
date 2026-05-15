import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import hegel/internal/session

const table_name = "hegel_registry"

const session_key = "session"

@external(erlang, "hegel_ffi", "ets_new")
fn ets_new(name: String) -> Dynamic

@external(erlang, "hegel_ffi", "ets_insert")
fn ets_insert(table: Dynamic, key: String, value: anything) -> Nil

@external(erlang, "hegel_ffi", "ets_lookup")
fn ets_lookup(table: Dynamic, key: String) -> Result(anything, Nil)

@external(erlang, "erlang", "binary_to_existing_atom")
fn table_ref(name: String) -> Dynamic

pub fn get_session() -> Result(process.Subject(session.SessionMessage), Nil) {
  ets_lookup(table_ref(table_name), session_key)
}

// TODO: I guess it's ok for these args to be typed Dynamic since they
// are not used. But confirm that.
pub fn start(_start_type: Dynamic, _start_args: Dynamic) {
  let table = ets_new(table_name)
  let name = process.new_name("session")

  let start_session = fn() {
    let result = session.start(name)
    case result {
      Ok(started) -> {
        ets_insert(table, session_key, started.data)
        Ok(started)
      }
      Error(err) -> Error(err)
    }
  }

  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(supervision.ChildSpecification(
    start: start_session,
    child_type: supervision.Worker(30_000),
    significant: False,
    restart: supervision.Temporary,
  ))
  |> supervisor.start
  |> result.map(fn(started) { started.pid })
}

pub fn stop() {
  Nil
}
