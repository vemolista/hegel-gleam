# AGENTS.md — hegel

`hegel-gleam` (the client) is a property-based testing library that communicates with [`hegel-core`](https://github.com/hegeldev/hegel-core) (the server). The server takes care of data generation and shrinking. The client manages the test loop and reports results to the user.

## Running the project

The project uses `flox` to define [dependencies](./.flox/env/manifest.toml) needed to run this project.

`just` is used as the command runner. When possible, use `just` commands to interact with the project. Use `just --list` to see a list of all available commands.

- **Build:** `just build`
- **Run:** `just run`
- **Format:** `just fmt`
- **Test:** `just test`
- **Test with debug logging:** `just test-debug` (sets `HEGEL_LOG=debug`)
- **Run conformance tests:** `just conformance`

## Architecture

The library is strictly dependant on running the [`hegel-core`](https://github.com/hegeldev/hegel-core) server. `hegel-gleam` communicates with the server over Erlang ports via FFI.

`hegel-gleam` is started as an OTP application and creates a singleton-like `Session` actor that owns the communication port to the server. The session is inserted into ETS so that `run` actors can send messages to the server.

- The `run` actor ows the state of running one test function, spawns case_workers and reports the final test outcome.
- The `case_worker` process runs user-code and returns an outcome.
- The `recorder` actor owns a list of drawn values during a test case.

File structure

- `src/hegel.gleam` — public API (`given`, `run`, `Settings`, `draw`)
- `src/hegel/internal/` — session actor, run worker, case worker, CBOR codec, protocol, recorder, test_case
- `src/hegel/generator/` — value generators (bool_, int_, float_, ...)
- `src/hegel_ffi.erl` — Erlang FFI for ports and ETS

## References

CRITICAL: When you encounter a reference (e.g., ./rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

Instructions:

- Do NOT preemptively load all references - use lazy loading based on actual need
- When loaded, treat content as mandatory instructions that override defaults
- Follow references recursively when needed

References:

- Gleam language reference https://tour.gleam.run/everything/
- Gleam patterns https://gleam.run/documentation/conventions-patterns-and-anti-patterns/
- Gleam packages - ./build/packages/<package>
- Hegel protocol reference https://hegel.dev/reference/protocol#schemas
- Hegel reference implementations - ./references/* (hegel-rust is the most complete)
