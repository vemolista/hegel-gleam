test:
	gleam test

test-debug $HEGEL_LOG="debug":
	gleam test

build:
	gleam build

run:
	gleam run

fmt:
	dprint fmt
	gleam format

build-conformance:
	#!/usr/bin/env bash
	set -euo pipefail
	mkdir -p build/conformance
	# Fail fast in case conformance package has build errors
	(cd conformance && gleam build)

	conformance_dir="{{ justfile_directory() }}/conformance"

	# For each conformance test, create a bash script that ./test/conformance/test_conformance.py
	# will execute to run the Gleam code in ./conformance/src/test_*.gleam
	for name in test_integers test_booleans test_floats; do
		wrapper="build/conformance/${name}"
		printf '#!/usr/bin/env bash\ncd %q && exec gleam run --target erlang --module %s -- "$@"\n' \
			"$conformance_dir" "$name" > "$wrapper"
		chmod +x "$wrapper"
	done

check-conformance: build-conformance
	uv run --with 'hegel-core>=0.4.0' --with pytest --with hypothesis \
		pytest test/conformance/test_conformance.py -v

conformance: check-conformance
