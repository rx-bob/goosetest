# Standalone package regression (E1.S4)

`integration/package_test.goose` is an independent verification executable. It
imports only `os`, checks the actual status supplied by the parent shell, and
compares captured output against the two embedded `.stdout` expectations. It does
not import goosetest or use framework assertions to judge framework behavior.

The passing project is copied from `examples/basic`. The negative replacement
`calculator_test.goose.data` changes the first expectation to 999 instead of 42.
A fatal sentinel immediately after that assertion detects failure to stop the
case. A marker inside the final test body proves later execution independently
of the framework's summary. Expected failure status is exactly 1, not merely any
nonzero status; a runtime abort cannot count as a successful regression check.

Run from the repository root with the pinned Goose v2026.3 compiler and installed
`goosefmt`. This external bootstrap procedure supplies process launching until
the native process adapter and independent verifier stories are implemented.
No new subprocess/native dependency is added to the runtime or checker.

```sh
(
    set -eu
    repo="$PWD"
    work=$(mktemp -d "${TMPDIR:-/tmp}/goosetest-package.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    export GOOSE_HOME="$work/cache"

    goose build --debug "$repo/integration/package_test.goose" -o "$work/oracle"
    cp -R "$repo/examples/basic" "$work/consumer"
    mkdir "$work/elsewhere"
    ln -s "$repo" "$work/package"
    sed 's@^import goosetest from "\.\./\.\.";$@import goosetest from "../package";@' \
        "$work/consumer/goosetest_root.goose" >"$work/root.goose"
    mv "$work/root.goose" "$work/consumer/goosetest_root.goose"

    verify_variant() {
        variant=$1
        location=$2
        binary="$work/$variant-$location"
        source_path="$work/consumer/goosetest_root.goose"
        if test "$location" = consumer; then
            source_path=goosetest_root.goose
        fi
        (
            cd "$work/$location"
            goose build --debug "$source_path" -o "$binary"
        )
        status=0
        (
            cd "$work/$location"
            "$binary"
        ) >"$binary.stdout" 2>&1 || status=$?
        "$work/oracle" "$binary.stdout" "$status" "$variant"
        echo "verified $variant from $location (status $status)"
    }

    goosefmt check --config "$repo/.goosefmt.toml" "$work/consumer"
    verify_variant passing consumer
    verify_variant passing elsewhere

    cp "$repo/integration/fixtures/package/calculator_test.goose.data" \
        "$work/consumer/test/calculator_test.goose"
    goosefmt check --config "$repo/.goosefmt.toml" "$work/consumer"
    verify_variant failing consumer
    verify_variant failing elsewhere

    goosefmt check --config "$repo/.goosefmt.toml" \
        "$repo/examples/basic" "$repo/integration/package_test.goose"
)
```

The application is outside the package tree. Only its root package declaration
changes; `package` is a link to the actual framework checkout. Builds from the
consumer root use a relative entry path; builds from the unrelated directory use
an absolute path. Each run has a distinct binary and captured log. A failed build
stops verification before any stale executable can run. The trap removes owned
copies, links, binaries, logs, and compiler cache without touching the checkout.

Expected matrix:

| Variant | Build/run directory | Child status | Later-body proof |
| --- | --- | ---: | --- |
| Passing | Consumer root | 0 | Three passing outcomes |
| Passing | Unrelated directory | 0 | Same output |
| Failing | Consumer root | 1 | Explicit marker in final test body |
| Failing | Unrelated directory | 1 | Same marker and expected/actual diagnostic |

The root declares the real package. Test modules import both `goosetest` and the
consumer's `src.calculator` directly, exercising separate package/consumer import
roots. The assertion implementation is neither copied nor redefined by the fixture.
