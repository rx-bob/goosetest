# Read-only source inventory (E2.S1)

`discovery::scan(inventory, project_path)` inventories required `src/` and `test/`
and optional `integration/`. An absent integration directory is valid; only
`ENOENT` counts as absence. Missing required roots, non-directory roots, permission
errors, invalid import segments, special files, and symlinks are errors.

This layer provides inventory and source bytes. Declaration parsing and owned
metadata manifests are described in [SYNTAX.md](SYNTAX.md) (E2.S2). Complete mirror
auditing and project validation are described in
[MIRRORS.md](MIRRORS.md) (E2.S3). The CLI follows in E2.S4. `main.build` wires the
filesystem adapter for the forthcoming CLI root. The test executable has its own
sidecar today. The public assertion facade `goosetest.goose` imports no discovery
or native filesystem code and has no native sidecar.

## Ownership and results

The caller owns growable arrays for `SourceFile` and `RootRecord` records,
exclusions, path bytes, source bytes, and error-path bytes. `new_inventory`
borrows these initially empty buffers through an `InventoryBuffers` value. Keep
their owners alive through every consumer of the inventory. A context is scanned
once; construct another for a new scan rather than reusing borrowed spans.

Each `SourceFile` contains path/source spans and a root kind (`Source`, `Unit`,
`Integration`). `path_text(inventory, file.path)` and `source_text(inventory, file)`
resolve spans into caller-owned arenas. Directory names, joined path scratch, and
per-file read buffers can leave scope without invalidating these records.

Only lowercase `.goose` regular files are read and recorded. Other regular files,
including `.goose.data`, are ignored but still count toward traversal/path budgets.
Directory segments and source basenames must be compiler-importable identifiers:
ASCII letters/underscore followed by letters/digits/underscore, excluding the
pinned compiler's 45 reserved keywords. Contextual words such as `inline` and
`from` remain valid. This is the compiler import contract, not a naming-style lint.
Directories with invalid segments are rejected even when empty.

The project path may contain spaces or non-identifier characters. Output paths
are project-relative and constructed with `/`. On this POSIX baseline a literal
backslash in an entry name is not a separator; it is rejected in import segments.
Top-level `test_support/` and `goosetest_generated/` are outside the three scan
roots and are not visited. Names with those spellings *inside* scanned roots are
ordinary directories, not hidden exclusions.

`complete` becomes true only after all roots close successfully and records are
sorted once by unsigned path bytes. Successful path order is independent of
creation order. Arena offsets reflect traversal order and are not stable IDs.
Configured roots retain target and pair identity for mirror matching. Legacy
roots retain the `src`/`test`/`integration` behavior. Explicit exclusions are
checked before parsing or directory descent, so excluded symlinks and contents
are not opened. Test roots admit only names ending in `_test.goose`; this helper
filter is configured-mode behavior. `.goose.data` is ignored in every mode.

`status(inventory)` is 0 only for a completed, error-free scan, including valid
empty roots. Otherwise it is 2. Partial records remain available for diagnosis but
must never be consumed as a complete manifest. The first error wins and retains
its offending path, configured limit (when applicable), and native errno.
`error_text(inventory)` renders those fields for a caller; discovery itself prints
nothing. An exhausted path arena cannot prevent retaining the separate error path.

## Finite limits

| Limit | Default | Accounting |
| --- | ---: | --- |
| `max_entries` | 65536 | Every existing root/child entry inspected, including ignored regular files |
| `max_depth` | 64 | Root directories have depth 0; each nested directory adds 1 |
| `max_path_bytes` | 4096 | Bytes in each normalized relative entry path |
| `max_path_storage_bytes` | 8388608 | Sum of relative path bytes for all accepted visited entries |
| `max_file_bytes` | 1048576 | Source bytes in one `.goose` file |
| `max_source_bytes` | 67108864 | Total retained source bytes across all roots |

All limits are independently injectable and nonnegative; zero is valid. Exact
bounds succeed. The first entry or byte exceeding a budget fails with its path and
limit name/value. Dot entries and absent optional integration do not consume an
entry. The two empty required roots consume two entries and seven path bytes.
Files inherit their containing directory's depth. File-record capacity is bounded
by the entry budget; stack capacity is bounded by depth plus one.

The native project-path input has the platform's `PATH_MAX` bound, separately from
relative inventory paths. The separate error-path buffer preserves offending input.
Joined child scratch may contain a bounded parent path plus one native `NAME_MAX`
entry and separator. File-read scratch is bounded by the smaller remaining source
budget and per-file limit, and is discarded on failure. Retained content is appended
only after a complete successful read. If both byte budgets are equal when a read
exceeds them, the per-file limit is reported first.

## Filesystem boundary

The initial supported environment remains macOS arm64 with Goose v2026.3.
`src/platform/filesystem.goose` contains the single canonical set of externs;
`native/filesystem.c` uses system APIs only. The installed stdlib's newline-delimited,
unbounded directory listing and whole-file reader cannot enforce this contract.

The walker is iterative depth-first. It holds one directory stream per depth and
keeps parent descriptors open while visiting children. Native iteration returns
one raw filename at a time; newline-containing filenames cannot split entries.
`fstatat(..., AT_SYMLINK_NOFOLLOW)` classifies entries. `openat` with `O_NOFOLLOW`
opens each single child segment through its retained parent, so a link inserted
between inspection and opening is rejected. Reads additionally verify a regular
file and use `O_NONBLOCK` to avoid blocking on a replacement FIFO.

Every scanned root/descendant link is rejected, including dangling links, directory
cycles, and links to files. The project pathname's ancestors may resolve through
symlinks; this is not a promise to reject every link in its absolute location.
A directory already opened remains bound to its descriptor if renamed. Inventory
is read-only, but is not an atomic filesystem snapshot under concurrent edits.
Detected read/list/inspection errors fail the scan rather than hiding omissions.

File reads check both initial size and actual bytes, consuming at most one probe
byte beyond the budget without appending that byte. EINTR retries are bounded at
16. All directory/project handles are closed on normal and error paths. Cleanup
preserves the first failure rather than replacing it with a secondary close error.

## Reproducible verification

Run as an unprivileged user so permission-denial fixtures actually fail access.
The suite explicitly rejects a root-user run rather than silently skipping those
checks. The self-host root owns scratch directories. The independent verifier
supplies a temporary parent that also cleans up after a fatal assertion. Native
test-only `chmod`/symlink helpers stay outside the production adapter; permission
modes are restored immediately after the scan.

From the repository root:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project .
goosefmt check --config .goosefmt.toml src/discovery src/platform \
    test/discovery test/platform test_support/filesystem.goose
```

Expected: generated tests pass with process status 0 and style status 0. Independent
builtin assertions check:

- Empty/nested roots, missing roots, optional integration, and ignored helper roots.
- Exact path/source ownership after temporary join/input scopes return.
- Two opposite-order trees, each with exactly 350 files and 70 nested directories;
  every sorted path and associated source content is checked, with 422 total entries.
- All six exact/one-over limits, negative limits, and no retained-budget overrun.
- Permission-denied files/directories, cycles, dangling/file links, invalid names,
  reserved words, literal backslashes, and newline-containing filenames.
- A deterministic invalid-handle iterator error, and file/directory links inserted
  after successful inspection but before opening.
- Descriptor counts before/after success and failure; bounded reads, empty files,
  invalid child names, and preserved errno distinctions.

Native sources in `goosetest_root.build` deliberately have distinct basenames. The pinned compiler uses basenames for native object files, so giving
a test helper the same basename as the production adapter overwrites its object.

The independent self-host verifier checks the discovered inventory and runs a
copy with an injected framework assertion failure. It observes the actual child
status externally, so a broken success verdict cannot certify itself. The copy,
compiler cache, and scratch parent are disposable; the checkout stays unchanged.
Run it from the repository root:

```sh
goose build --debug scripts/verify.goose -o /tmp/goosetest-verify
/tmp/goosetest-verify
```
