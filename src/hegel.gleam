import hegel/internal/app
import hegel/internal/generator/core
import hegel/internal/run
import hegel/internal/test_case.{type TestCase}

pub type Settings {
  Settings(test_cases: Int)
}

pub fn default_settings() -> Settings {
  Settings(test_cases: 100)
}

pub fn run(settings: Settings, body: fn(TestCase) -> Nil) -> Nil {
  let assert Ok(session) = app.get_session()
  run.run_test(session, body, settings.test_cases)

  Nil
}

pub fn given(body: fn(TestCase) -> Nil) -> Nil {
  run(default_settings(), body)
}

pub const draw = core.draw
