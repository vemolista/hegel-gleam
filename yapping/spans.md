# Spans, non-basic generators, and `StopTest`

This note records the intended mental model for Hegel spans and the client-side
handling expected when the server replies with `StopTest`.

## Basic vs non-basic generators

A **basic generator** is a generator that can be represented as one Hegel
protocol schema and one parser for the generated CBOR value. Drawing a basic
generator is a single `generate` command:

```text
schema-backed generator -> generate(schema) -> raw CBOR -> parse
```

Examples include primitive integers, booleans, floats, strings, and collections
whose children are also basic. For example, a list of integers can become a
single protocol schema:

```json
{
  "type": "list",
  "elements": { "type": "integer" },
  "min_size": 0,
  "unique": false
}
```

A **non-basic generator** is one that cannot be expressed as one static schema.
Common examples are:

- `flat_map`, because later generator structure depends on an earlier drawn
  value.
- `filter` with an arbitrary client-side predicate.
- `map` when its source is already non-basic.
- Lists, dicts, tuples, or `one_of` values containing non-basic child
  generators.
- Composite generators implemented as ordinary client code that calls `draw`.

For these cases, the client must draw procedurally: it runs generator code and
performs one or more smaller protocol operations against the same test case.

## What spans are

Spans are protocol-level markers around a group of generation choices. They do
not directly generate values. The protocol commands are:

- `start_span(label)` — mark the start of a labeled group of choices.
- `stop_span(discard)` — mark the end of the current group.

The `label` identifies the kind of span, such as list, tuple, flat-map, filter,
or a deterministic label for a user composite. The `discard` flag tells the
backend that the choices inside the span should be excluded from shrinking.

Spans give the backend enough structure to replay and shrink client-side
composition. Without spans, the backend would only see a flat sequence of
smaller draws, with no indication that several choices together represented one
higher-level generator value.

The general fallback shape is:

```text
start_span(label)
  draw one or more child generators
  maybe ask collection sizing questions
  maybe reject discarded attempts
stop_span(discard: false)
```

If an attempted draw is intentionally rejected, such as a failed filter attempt,
the span should be stopped with `discard: true` so the rejected attempt does not
participate in shrinking.

## Collection fallback

Variable-length collections have an additional protocol helper because the
server should still control collection size even when it cannot generate each
element itself.

For a list whose element generator is basic, the client should prefer one
schema-backed `generate` command using the protocol `list` schema. For a list
whose element generator is non-basic, the client should use the collection
protocol inside a span:

```text
start_span(LIST)
collection_id = new_collection(min_size, max_size)
items = []

while collection_more(collection_id) {
  item = draw(element_generator)

  if item cannot be used, for example because it duplicates a unique item {
    collection_reject(collection_id)
  } else {
    items.append(item)
  }
}

stop_span(discard: false)
```

This split lets the backend decide and shrink the length while the client draws
each element using arbitrary generator logic.

Dict/map fallback is the same idea, except each accepted collection entry draws
a key and then a value. Duplicate keys should call `collection_reject` so the
backend knows the most recent collection slot did not become an accepted entry.

Tuples do not need the collection protocol because their size is fixed. If any
child is non-basic, draw each child inside a tuple span.

## Examples of non-basic fallback

### `flat_map`

`flat_map` is non-basic in the general case because the second generator depends
on a value drawn from the first generator:

```text
start_span(FLAT_MAP)
intermediate = draw(source)
next_generator = f(intermediate)
result = draw(next_generator)
stop_span(discard: false)
```

### `filter`

For a general filter predicate, draw attempts from the source generator until
one passes. Rejected attempts should be discarded:

```text
for a small retry limit {
  start_span(FILTER)
  value = draw(source)

  if predicate(value) {
    stop_span(discard: false)
    return value
  }

  stop_span(discard: true)
}

assume(false)
```

The Rust reference retries filters a small number of times and then rejects the
whole test case with an assumption failure.

### `map`

If the source generator is basic, `map` can usually stay basic by reusing the
source schema and composing the transform into the parse step. If the source is
not basic, `map` should start a mapped span, draw the source, apply the
transform, and stop the span.

## `StopTest` handling

The maintainer guidance is that `StopTest` should be understood as
`StopTestCase`: the server has already decided to stop the current test case.
The client should abort the current test case iteration and move on to the next
one.

Important rule:

> If the client receives `StopTest` while running a test case, it should not send
> `mark_complete` for that test case.

The server already has the information needed to classify the case. A common
reason for `StopTest` is that the test case consumed too much entropy; in that
case the correct status is `OVERRUN`, which the server knows but the client may
not. Sending `mark_complete VALID` after such a response would be wrong.

Client-side handling should therefore be:

```text
on StopTest from generate/start_span/stop_span/collection operation:
  abort the current case worker
  record the local outcome as overrun/aborted
  do not send mark_complete
  perform only local cleanup needed to forget the stream/worker
```

Shelby follows this shape by converting backend `StopTest` into a sentinel panic,
turning that into an `Overrun` case-worker outcome, and intentionally skipping
`mark_complete` for that outcome.

## `StopTest` as a reply to `mark_complete`

There is a known server-side wrinkle: the server may currently allow internal
`StopTest` exceptions from its `mark_complete` handling to bubble back to the
client. The maintainer described this as unintended and likely something the
server should suppress.

That means clients should be defensive around terminal completion:

- `mark_complete` is terminal from the client's perspective.
- A `StopTest` response to `mark_complete` should not be reported as a user test
  failure.
- It is reasonable to ignore or suppress `StopTest` from `mark_complete`, because
  by then the client has already told the server the test-case result.

The Rust reference effectively does this by ignoring the result of the
`mark_complete` request and then closing the stream.

## Concurrency caveat

Spans are ordered protocol structure. If two threads draw concurrently from the
same test case, their operations can interleave between `start_span` and
`stop_span`, corrupting the shrink-friendly shape seen by the backend. If a
client supports cloned/shared test cases, it should serialize backend operations
and should document that concurrent composite draws are not safely replayable
unless the client and backend provide stronger ordering guarantees.
