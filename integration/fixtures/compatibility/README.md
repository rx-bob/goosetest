# E1.S1 compatibility fixtures

Run from the repository root with the pinned compiler described in
[compatibility.md](../../../docs/compatibility.md).

`contract/` is a miniature compiler probe package, not the production runtime.
`users/` exercises its bridge from two namespaces. `scenarios.goose` checks hard
stops, continuation, nested recovery, const-generic inputs, and storage references.
The standalone `integration/compatibility_test.goose` is the root entry point.
Built-in assertions are the oracle; no goosetest implementation judges itself.

The following shell commands are an external bootstrap procedure, not repository
automation. They require no process adapter or additional language dependency.
Every compiler rejection is checked for its specific diagnostic, not just failure.
Build failures stop the procedure before any binary can run.

```sh
(
    set -eu
    work=$(mktemp -d "${TMPDIR:-/tmp}/goosetest-compatibility.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    export GOOSE_HOME="$work/cache"
    fixtures=integration/fixtures/compatibility

    goose build --debug integration/compatibility_test.goose -o "$work/positive"
    "$work/positive"
    goosefmt check --config .goosefmt.toml integration

    cp -R "$fixtures/contract" "$work/contract"
    for name in outside_boundary shadowed_bridge const_mutation shrink_borrow receiver_lookup main_result; do
        cp "$fixtures/negative/$name.goose.data" "$work/$name.goose"
        if goose check "$work/$name.goose" >"$work/$name.log" 2>&1; then
            echo "unexpected compile success: $name" >&2
            exit 1
        fi
        case "$name" in
            outside_boundary) expected='no enclosing call of goosetest::run_case' ;;
            shadowed_bridge) expected='no matching overload for call to assert_eq' ;;
            const_mutation) expected='cannot assign through this path' ;;
            shrink_borrow) expected='cannot clear bytes while first is still used' ;;
            receiver_lookup) expected='unknown function or member: read_number' ;;
            main_result) expected='fn main() takes no parameters and returns nothing' ;;
        esac
        grep -F "$expected" "$work/$name.log"
    done

    cp "$fixtures/exit_status.goose.data" "$work/exit_status.goose"
    goose build --debug "$work/exit_status.goose" -o "$work/exit_status"
    status=0
    "$work/exit_status" || status=$?
    test "$status" -eq 7
)
```

Expected: positive executable exits 0; six invalid programs fail with the selected
diagnostic; explicit status executable exits 7; style check exits 0. No output
parsing is used to decide whether the positive runtime checks passed.

`global_bridge.goose.data` is a **valid** compiler input retained as a formatter
defect reproducer. Copy it to a temporary `.goose` path and compare `goose check`
with `goosefmt check --config "$PWD/.goosefmt.toml"`. The latter reports G011 for
the global qualifier. It is deliberately separate from the negative matrix.

All `.data` inputs stay inert until copied into a disposable project. Package
declarations in the negative roots expect `contract/` beside the materialized
file. The procedure cleans its own binaries, generated C, logs, and cache.
