import envoy
import gleeunit
import logging

pub fn main() -> Nil {
  logging.configure()
  case envoy.get("HEGEL_LOG") {
    Ok("debug") -> logging.set_level(logging.Debug)
    Ok("info") -> logging.set_level(logging.Info)
    Ok("warning") -> logging.set_level(logging.Warning)
    Ok("error") -> logging.set_level(logging.Error)
    _ -> Nil
  }
  gleeunit.main()
}
