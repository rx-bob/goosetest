# Project validation and mirror policy

After a successful inventory, `inspect_project` validates roots, configured
mirror policy and declarations before listing or generation. Only status 0 admits
the complete selected inventory. Neither this layer nor syntax scanning executes
project code, writes files or invokes a compiler. The CLI selects configured
targets before scanning; filters are applied only after discovery and declaration
validation.

## Layout contract

Legacy projects use strict correspondence: every
`src/<path>/<name>.goose` needs exactly `test/<path>/<name>_test.goose`, and
every unit suite needs its source counterpart. Configured targets choose
`mirror.policy` `strict` or `off`. Strict targets declare source/test root pairs;
matching uses relative module stems, independent of the root names. Each unit
test root needs exactly one pair, and each configured source root must have an
unambiguous pair. Integration roots have no mirror pair. Off targets do not scan
production roots and do not claim source correspondence.

Configured `exclude` entries name exact project-relative files or
slash-terminated directory prefixes. Exclusion happens before opening a file or
descending a directory; excluded content is not syntax-checked. There are no
globs. Root entries, facades, native sources, `test_support/` and
`goosetest_generated/` are outside discovery unless explicitly placed under a
configured root.

Integration suites need no source counterpart and may import multiple production
modules. In legacy roots, non-test `.goose` files under `test/` or
`integration/` are layout errors. Configured test roots discover only filenames
ending in `_test.goose`; ordinary helpers remain available to imports but are
not suites. Other file types follow inventory rules. Invalid source fixtures
should use a data suffix until materialized in a disposable project. Every
admitted suite needs a valid test declaration. Disabled tests count. An empty
configured target remains invalid even when another target has cases.

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
record. Otherwise syntax errors retain the first-error path and location.
On an incomplete filesystem scan, report the inventory error; on layout failure,
report audit records; on syntax failure, report `manifest_error_text`. All such
outcomes have project status 2. Configured target selection controls which roots
enter this boundary. Case and suite filters consume the complete admitted
manifest; they do not hide malformed selected suites or reduce type checking for
a target that has matching cases.

Temporary source/unit indices are sorted by relative module stem, then merged
linearly. Sorting full filenames would be incorrect: adding `_test` changes order
for names such as `a` and `a0`. Storage is bounded by the complete inventory's file
count (itself bounded by `Limits.max_entries`): each file occupies at most one
index and each result consumes at least one file. No second path arena or new
independent unbounded collection is introduced. Construct fresh contexts per run.

## Verification

Mirror unit cases and cross-module discovery cases run through generated discovery.
The self-host root supplies owned scratch directories. From the repository root:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project .
```

Expected: the generated suite exits 0. Builtin assertions verify 350 exact pairs,
ordering traps, nested/prefixed names, missing and orphaned paths from a rename,
bad filenames, incomplete inputs, independent integration suites, empty suites,
empty projects and ignored roots. The original POC is read without alteration;
its path-only audit reports `src/workspaces/archive.goose` and expected
`test/workspaces/archive_test.goose`. Its historical syntax is intentionally not
passed through the modern declaration scanner. Syntax regressions additionally
verify bad-name paths and a valid disabled-only suite.
