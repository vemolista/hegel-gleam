import hegel
import hegel/generator/float_

pub fn floats_test() {
  use tc <- hegel.given()
  let num =
    hegel.draw(
      tc,
      float_.new()
        |> float_.max(10.0)
        |> float_.min(1.0)
        |> float_.exclude_max()
        |> float_.exclude_min()
        |> float_.build(),
    )

  assert num <. 10.0
  assert num >. 1.0
}
