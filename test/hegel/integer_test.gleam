import exception
import gleam/int
import hegel
import hegel/generator/int_

pub fn generates_within_bounds_test() {
  use tc <- hegel.given()
  let i =
    hegel.draw(tc, int_.new() |> int_.max(100) |> int_.min(1) |> int_.build())

  case 1 <= i && i <= 100 {
    True -> Nil
    False -> panic
  }
}

pub fn some_test() {
  use tc <- hegel.given()
  let i = hegel.draw(tc, int_.new() |> int_.build())

  assert i + 1_659_687 != 16
}

pub fn will_fail_test() {
  let assert Error(_) =
    // Crashes if a 0 or an even int is generated, which is practically every time
    exception.rescue(fn() {
      use tc <- hegel.given()
      let i = hegel.draw(tc, int_.new() |> int_.build())

      let remainder = case int.remainder(i, 2) {
        Ok(v) -> v
        Error(_) -> 0
      }
      assert remainder != 0
    })
}
