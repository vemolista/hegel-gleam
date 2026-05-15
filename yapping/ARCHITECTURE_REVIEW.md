# hegel architecture review

## Scope

This review looks at the current implementation in `src/`, using the Hegel protocol reference, the actor/process archetypes from the supplied article, and the Rust implementation at `/Users/tomas/repos/github.com/hegeldev/hegel-rust` as references. Existing markdown documents in this repository were intentionally not considered.

## Current shape

hegel is already organized around a useful split:

- `hegel.gleam` exposes the public API.
- `hegel/internal/app.gleam` starts and registers the long-lived session actor.
- `hegel/internal/session.gleam` owns the Hegel server port and multiplexes protocol streams.
- `hegel/internal/run.gleam` drives one property-test run.
- `hegel/internal/case_worker.gleam` runs user code for one test case.
- `hegel/generator/*` builds schemas, sends `generate`, and parses generated values.
- `hegel/internal/protocol.gleam` encodes and decodes Hegel packets.
- `hegel/internal/cbor.gleam` wraps CBOR map construction and decoding.

The high-level design is close to the right model for BEAM: one long-lived process owns the external connection, short-lived workers execute user code, and a per-run coordinator manages test-run lifecycle.

```diagram
╭────────────╮       ╭──────────────╮       ╭──────────────╮
│ Public API │──────▶│ Run actor    │──────▶│ Case workers │
╰────────────╯       ╰──────┬───────╯       ╰──────┬───────╯
                            │                      │
                            ▼                      ▼
                     ╭──────────────╮       ╭──────────────╮
                     │ Session      │──────▶│ Hegel server │
                     │ actor / port │◀──────│ port         │
                     ╰──────────────╯       ╰──────────────╯
```

## Actor archetype assessment

| Process/module | Current role | Fit | Main concern |
|---|---|---:|---|
| `session` actor | Resource owner for the port, stream registry, pending replies, message IDs; also a router for inbound packets | Mixed | It owns the right state, but also contains routing policy, lifecycle, handshake, versioning, packet dispatch, stream allocation, and some failure behavior. |
| `run` actor | Per-run coordinator | Mixed | It is partly a resource owner for run state, partly a router from run-stream events to case workers, and partly result formatter/error-policy owner. |
| `case_worker` process | Worker | Good | It does one user-code execution and reports an outcome. It has some extra protocol completion details but is conceptually clear. |
| `recorder` actor | Resource owner | Good but probably avoidable | It owns one list of drawn values, but it only exists for one case and could be replaced by local data if draw recording is made synchronous/local. |
| OTP supervisor in `app` | Observer/supervisor | Thin but incomplete | It starts the session, but the child is temporary and session failure/recovery behavior is unclear. |

The most important actor-archetype rule is: every process should have one job. hegel mostly follows this, but `session` and `run` are beginning to become “god processes with mailboxes”.

## Reference comparison: Hegel Rust

The Rust client has a clear conceptual split that hegel can mirror without copying its implementation style:

1. `server/protocol/packet.rs` only knows how to read/write packets.
2. `server/protocol/connection.rs` owns the connection writer, stream registry, stream ID allocation, and background packet dispatch.
3. `server/protocol/stream.rs` owns per-stream request/reply message IDs and blocking receive/send operations.
4. `server/session.rs` owns Hegel session lifecycle and test-run protocol.
5. `backend.rs` defines a transport-independent `DataSource`/`TestRunner` boundary.
6. Generators build schemas and parse values, while draw execution goes through the data source.

hegel currently has most of these concepts, but some boundaries are blurred:

- `session.gleam` combines connection, router, stream registry, stream ID allocation, pending replies, handshake, server startup, and version validation.
- `generator/generator.gleam` knows both generator semantics and transport response envelope/error handling.
- `run.gleam` both implements the run protocol and formats final user-facing panic output.

## Findings and proposed simplifications

### 1. Split `session` responsibilities by concept, not necessarily by process

`session` should remain the sole resource owner for the port and its mutable connection state. However, the module can be simplified by extracting pure helpers/types for:

- Hegel server startup and handshake.
- Stream ID and message ID allocation.
- Pending reply bookkeeping.
- Packet dispatch decisions.
- Protocol-version compatibility checks.

This does not require adding more actors. The important simplification is that the actor callback becomes a small state transition over well-named operations.

Recommended shape:

```diagram
╭──────────────────────────────╮
│ session actor                │
│ - owns port                  │
│ - owns stream registry       │
│ - owns pending replies       │
╰──────┬──────────┬────────────╯
       │          │
       ▼          ▼
╭──────────╮  ╭───────────────╮
│ startup  │  │ dispatch/pure │
│ helpers  │  │ helpers       │
╰──────────╯  ╰───────────────╯
```

Why this helps:

- Keeps the process archetype clear: `session` is a resource owner.
- Reduces risk when updating protocol details.
- Makes packet dispatch easier to unit test without a live port.

Concrete cleanup candidates:

- Remove unused or no-op messages such as `Receive`, or implement them if they are intended API.
- Remove stored state fields that are not used for behavior, such as `handshake_complete` and possibly `protocol_version`, unless future code reads them.
- Convert `PortExit`, `PortDown`, and `PortUnexpected` from no-ops into explicit session failure handling, or document and centralize why they are ignored.
- Replace `panic` on missing stream message ID with an internal error path that replies to the caller.

### 2. Introduce a small per-stream abstraction

The Hegel protocol is stream-oriented. Rust makes this explicit with a `Stream` object that handles request/reply operations against a connection. hegel has a `Stream` record, but message IDs and pending replies live entirely in `session` and callers pass raw `stream_id` values around.

A small stream API would reduce accidental misuse:

- `stream.request(stream, payload)`
- `stream.reply(stream, request_packet, payload)`
- `stream.close(stream)`

In Gleam this can still delegate to the session actor; it does not need to be another process. The goal is to stop spreading `(session, stream_id, message_id)` plumbing through `run`, `case_worker`, and `generator`.

Benefits:

- Fewer raw IDs passed across the codebase.
- Cleaner run/case code.
- Easier enforcement of odd client-created stream IDs and per-stream message sequencing.

### 3. Keep `run` as the run lifecycle owner, but move formatting out

`run.gleam` currently coordinates the test stream, spawns case workers, tracks in-flight monitors, stores final results, handles internal failures, and formats user-facing panic messages. The lifecycle ownership is appropriate; the formatting is not essential to the actor.

Simplification:

- Keep the actor responsible for producing `Result(TestRunResult, InternalError)`.
- Move final failure-message rendering to a pure helper, ideally outside the actor path.
- Consider a `RunEvent` decoder module or section for event decoding (`test_case`, `test_done`) so the actor callback reads as event handling rather than CBOR decoding plus state management.

This mirrors the Rust split where `ServerTestRunner` handles protocol flow and the public runner/API handles final user-facing behavior.

### 4. Reconsider concurrent case workers

hegel spawns every test case as an unlinked worker and tracks monitors. This is valid BEAM style, and the worker role is clean. However, the Hegel Rust reference processes normal test cases synchronously inside the run loop and separately handles final replay cases after `test_done`.

The current concurrent design adds complexity:

- `in_flight` monitor map.
- `replays_remaining` bookkeeping.
- Race-sensitive `send_reply_sync` before spawning.
- Extra crash-path cleanup.

If Hegel core does not require multiple case streams to run concurrently, a simpler first implementation would run one case at a time from the run actor:

1. Receive `test_case` event.
2. Acknowledge it.
3. Run case worker synchronously via a short-lived process or direct protected call.
4. Record outcome.
5. Return to the event loop.

Keeping case workers is still useful to isolate user panics. The simplification is to avoid supporting multiple in-flight cases unless the protocol/runtime needs it. If concurrency is intentionally desired, keep it but document it as a deliberate gatekeeper/router decision and test the ordering assumptions.

### 5. Separate generator schema/parsing from draw transport

Each generator currently stores:

- `schema`
- `parse`
- `display`

That part is clean and similar to Rust's `BasicGenerator`. The less clean part is that `generator.draw` also knows the transport envelope (`{"command": "generate", "schema": ...}`), server error shapes, and panic sentinels.

Suggested boundary:

- Generators build schemas and parse raw generated CBOR values.
- A test-case data source sends `generate`, unwraps `result`, maps server errors to a typed outcome, and returns raw CBOR to the generator parser.

This would remove the repeated “sometimes parse `result`, sometimes parse raw nested value” logic from leaf generators and collection generators. It would also match Rust's `DataSource` boundary more closely.

Practical small step:

- Add one internal helper that unwraps `CBMap {"result": value}` into `value` before calling a generator parser.
- Update generator `parse` functions to expect raw values only.

This is likely one of the highest-value cleanups because it removes transport concerns from every generator module.

### 6. Replace panic sentinels with typed internal outcomes where possible

hegel uses panic strings for internal control flow:

- `ASSUME_FAIL`
- `__hegel_STOP_TEST`
- `__hegel_INTERNAL: ...`

Some panic catching is unavoidable because user test code can panic. But internal transport/server outcomes should be typed until they cross into user-code execution.

Simplification options:

- Let draw return `Result(a, DrawError)` internally and convert to user-visible panic only at the boundary where Gleam's public API requires it.
- Or keep panic-based control flow for now, but isolate sentinel construction and matching in one module so generator and case worker do not share string constants implicitly.

This would make internal failures easier to distinguish from user failures and would reduce reliance on exact panic string matching.

### 7. Make protocol compatibility follow the reference model

The current session requires an exact protocol version match (`0.12`). The Rust client accepts a supported range, currently a single-version range but represented as `(lo, hi)`. The protocol reference defines the handshake as `Hegel/{version}` and expects client/server compatibility validation.

Recommendation:

- Represent supported protocol versions as a range or explicit list.
- Produce a clear error message that names the supported versions and the server version.
- Keep Hegel core version and protocol version close together, but do not assume they are the same concept.

This is a small cleanup with good operational value.

### 8. Clarify session lifecycle and recovery

`app.gleam` starts the session under a supervisor, registers it in ETS, and marks the child as `Temporary`. If the session dies, it is not clear whether callers should get a new session, a stale ETS subject, or a failure.

Rust's session getter checks whether the server exited and creates a new session when needed. hegel can choose either behavior, but it should be explicit:

- For a simple library: fail fast and require process/application restart.
- For a robust library: restart the session and update the registry.

The current middle ground is confusing. The smallest cleanup is to make `get_session` fail clearly if the registered session is gone, and to make supervisor restart policy match the desired behavior.

### 9. Keep FFI thin, but remove unused surface area

The FFI file is intentionally thin, which is good. However, it currently exposes process-dictionary helpers (`pd_get`, `pd_put`, `pd_increment`) that are not part of the main architecture shown in `src/` and do not fit the “minimal FFI” rule.

Recommendation:

- Remove unused FFI exports once confirmed unused by tests.
- Keep FFI to ports, executable lookup, and ETS only if ETS remains necessary.

### 10. Consider whether ETS registration is needed

ETS is used as a global registry for the session subject. Since the OTP app starts exactly one session actor with a process name, a named process may be enough. If Gleam's APIs make direct named lookup awkward, ETS is acceptable, but it adds global mutable state outside the session owner.

Recommendation:

- Prefer named actor lookup if practical.
- If ETS remains, keep it isolated to `app.gleam` and define the expected behavior when the subject becomes stale.

## Suggested priority order

1. **Clean generator parsing boundary.** Make parsers consume raw values and centralize `result`/error envelope handling in draw/data-source code.
2. **Trim and clarify `session` state/messages.** Remove unused messages/fields and give port exit/unexpected messages explicit behavior.
3. **Add a per-stream helper API.** Reduce raw stream/message ID plumbing outside `session`.
4. **Move run-result formatting out of the actor path.** Keep `run` focused on lifecycle and state.
5. **Decide on case concurrency.** Either document/test it as intentional or simplify to one case at a time.
6. **Improve protocol compatibility and session recovery errors.** Use clearer version checks and lifecycle behavior.
7. **Prune unused FFI helpers.** Keep the Erlang side minimal.

## What I would not change yet

- Do not add a large abstraction hierarchy. The codebase is still small.
- Do not split every concept into a new process. The BEAM actor model helps when a process owns state or isolates failure; pure protocol helpers do not need mailboxes.
- Do not replace the port-owning session actor with direct calls from workers. The session actor is the correct owner for the Hegel transport.
- Do not optimize generator display/recording before cleaning the result-envelope boundary.

## Summary

hegel's architecture is directionally sound: a long-lived session owns the transport, a run actor owns test-run lifecycle, and case workers isolate user code. The main cleanup opportunity is to sharpen boundaries so each process has one archetypal role. The most useful simplifications are local and incremental: centralize transport-envelope handling, make streams a clearer API, reduce mixed responsibilities in `session` and `run`, and make lifecycle/error behavior explicit.
