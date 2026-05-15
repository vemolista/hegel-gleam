import exception
import hegel/internal/case_worker

pub fn extract_exception_success_test() {
  let assert Error(exception) = exception.rescue(fn() { panic as "hi" })

  assert "hi" == case_worker.extract_panic_message(exception)
}
