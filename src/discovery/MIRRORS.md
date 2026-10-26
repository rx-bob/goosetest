# Complete project validation (E2.S3)

After a successful filesystem `scan`, call `inspect_project(audit, manifest,
inventory)`. It audits the complete inventory before scanning declarations.
Only `project_status(audit, manifest) == 0` admits a project to later selection,
generation or listing. Neither this layer nor the syntax layer executes project
code, writes files or invokes a compiler. CLI wiring follows in E2.S4.

## Layout contract

Every `src/<path>/<name>.goose` needs exactly
`test/<path>/<name>_test.goose`, and every unit suite needs its source counterpart.
Nested paths and similarly prefixed names match exactly. There are no exclusion
globs or file exemptions. Root entries and facades, `native/`, `test_support/` and
`goosetest_generated/` are outside the scanned roots. Placing a helper under
`test/` or `integration/` does not exempt it.

Integration suites need no source counterpart and may import multiple production
modules. Both test roots admit only `.goose` files with a nonempty name before
`_test.goose`. Other file types remain governed by the inventory layer; invalid
fixture source should retain a data suffix until materialized in a disposable
project. Every suite must contain at least one valid test declaration. Disabled
tests count. A project with no discovered cases fails full validation.

## Audit results and ownership

Create `MirrorAudit` with `new_mirror_audit(records)`, passing an empty caller-owned
`MirrorRecord` array. Keep both the inventory and record owners alive and immutable
while consuming results. Records retain inventory indices, not borrowed temporary
strings. `mirror_record_text` renders the actual and expected paths on demand.

`audit_mirrors` is the path-only API. It retains all matched, missing, orphaned and
bad-filename records. A rename therefore reports both the new source's missing unit
file and the old test's missing source. Counters describe file correspondence,
never statement, branch or behavioral coverage. Integration files are counted
separately. A complete audit may contain violations: `mirror_status` returns 2
for violations or incomplete inventory, and 0 only for valid correspondence.
An empty path-only audit is valid; full validation additionally requires cases.

The coordinator stops before syntax if layout fails, preserving every layout
record. Otherwise syntax errors retain the existing first-error path and location.
On an incomplete filesystem scan, report the inventory error; on layout failure,
report audit records; on syntax failure, report `manifest_error_text`. All such
outcomes have project status 2. No selection parameter exists at this boundary;
future filtering must consume the completed result, not prune the inventory.

Temporary source/unit indices are sorted by relative module stem, then merged
linearly. Sorting full filenames would be incorrect: adding `_test` changes order
for names such as `a` and `a0`. Storage is bounded by the complete inventory's file
count (itself bounded by `Limits.max_entries`): each file occupies at most one
index and each result consumes at least one file. No second path arena or new
independent unbounded collection is introduced. Construct fresh contexts per run.

## Verification

`test/mirror_test.goose` is a transitional bootstrap executable with an explicit
native sidecar. Its parent supplies a nonexistent temporary fixture directory and
cleans that directory after success or failure. Example from the repository root:

```sh
GOOSE_HOME=/tmp/goosetest-mirror-cache goose build --debug test/mirror_test.goose -o /tmp/goosetest-mirror-test
python3 - <<'PY'
import pathlib, shutil, subprocess, tempfile
parent = pathlib.Path(tempfile.mkdtemp(prefix="goosetest-mirror-"))
try:
    subprocess.run([
        "/tmp/goosetest-mirror-test", str(parent / "projects"),
        str(pathlib.Path("poc/example_project").resolve()),
    ], check=True)
finally:
    shutil.rmtree(parent)
PY
```

Expected: `mirror tests passed`, exit 0. Builtin assertions verify 350 exact pairs,
ordering traps, nested/prefixed names, missing and orphaned paths from a rename,
bad filenames, incomplete inputs, independent integration suites, empty suites,
empty projects and ignored roots. The original POC is read without alteration;
its path-only audit reports `src/workspaces/archive.goose` and expected
`test/workspaces/archive_test.goose`. Its historical syntax is intentionally not
passed through the modern declaration scanner. Syntax regressions additionally
verify bad-name paths and a valid disabled-only suite.
