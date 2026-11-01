# Architecture and operational limits

The CLI separates read-only discovery from generation, artifact publication,
compilation, and execution. The assertion runtime can be imported without the
CLI's native filesystem or process adapters.

## Execution flow

1. `src/config/` loads the bounded project config, if present. Legacy projects
   inventory `src/`, `test/`, and optional `integration/`; configured projects
   inventory only roots belonging to selected targets, applying exclusions before
   visiting entries. Strict targets audit declared unit pairs; off targets do not
   scan production roots. All inventories use explicit entry, path, source, and
   recursion budgets and reject symlinks in visited roots.
2. The lexer and declaration parser recognize real source structure, comments,
   strings, signatures, and supported metadata. Stable case IDs combine relative
   source path, namespace, and function name. Display labels do not affect IDs.
3. `src/generation/` emits bounded modules from the complete audited manifest.
   Selection changes execution, not compile validation: disabled and filtered
   tests retain cold call paths with valid assertion recovery ancestry.
4. Artifact publication owns only manifest-listed generated files. Ownership
   locks exclude concurrent writes. Atomic writes and ownership metadata support
   interrupted-run recovery without claiming or deleting arbitrary user files.
5. The CLI invokes the configured compiler with `build --debug` on the unchanged
   authored legacy root or configured target entry, then runs each target's new
   executable in the project directory. Debug and optimized profiles map to
   `--debug -O0` and `-O2`. Each selected target has an independent entry sidecar
   and child process; unselected target sidecars are not compiled. Old execution
   output is removed before compilation. Failed builds never fall back to stale
   test output.
6. Generated wrappers call the runtime through case and phase recovery boundaries.
   The console reporter consumes finalized records; the root propagates status.

Each authored entry declares package imports and generated orchestration. Its
optional adjacent `.build` sidecar declares executable-specific native sources.
Configured target names determine the generated directory, binary, completion
record, and child cache partition. Package and native paths retain authored
resolution; the generator does not copy a production entry point or infer package
declarations from imports. Dependencies reached through imports in the selected
entry or its shared helpers remain part of that target's build.

## Runtime ownership and failures

`goosetest::Test` borrows caller-owned result tables and diagnostic/metadata arenas.
Case identities are copied into retained metadata before execution. Recorded
failures retain their phase and owned diagnostic text until reporting completes.
The reporter escapes terminal control bytes and identifies declaration locations.

Hard assertions use `return from goosetest::run_case`; generic global bridges
provide the public `t.assert_*` vocabulary. This compiler requires a matching
recovery ancestor even for code paths that would pass. Cold generated references
preserve it for disabled and filtered functions. Ordinary fatal Goose assertions
and native crashes have no equivalent recovery boundary.

Fixture construction is local to each fixture-using case. Setup, body, and cleanup
have separate recoverable phases; failed setup suppresses the body while cleanup
is still attempted. Suite hooks have their own failure records. Fail-fast is
observed after cleanup, preserving earlier failures. Exhausted storage marks the
run incomplete rather than dropping records and reporting success. See
[lifecycle](../src/runtime/LIFECYCLE.md) and [runtime storage](../integration/fixtures/runtime/README.md).

## Finite defaults

All sizes below are bytes unless stated otherwise. Discovery and generation
limits are fixed in the CLI; they are not configuration flags.

| Boundary | Default bounds |
| --- | --- |
| Filesystem inventory | 65,536 entries; depth 64; 4,096 bytes/path; 8,388,608 retained path bytes; 1,048,576 bytes/file; 67,108,864 source bytes total. |
| Syntax manifest | 1,048,576 bytes/file; 67,108,864 total bytes; 262,144 tokens/file; nesting 128; 4,096 suites; 65,536 cases; 8,388,608 text bytes. |
| Generated modules | 70,000 files; 67,108,864 source bytes; 4,194,304 path bytes; display labels and disabled reasons at most 1,024 decoded bytes each. |
| Runtime API defaults | 4,096 cases; 16,384 failure records; 1,048,576 diagnostic bytes; 1,048,576 metadata bytes. |
| CLI stage deadlines | Compilation 120 seconds; execution 120 seconds; termination grace 1 second. |
| Process adapter | 256 arguments; packed argv at most 65,536 bytes; cwd at most 4,096 bytes; deadline 1–86,400,000 ms; grace 0–60,000 ms. |
| Selection text | Literal filter at most 4,096 bytes. |

Generated runners set case capacity from the full discovered manifest and compute
metadata capacity from emitted identities and hook/skip records. They retain the
runtime failure and diagnostic limits. Those generated capacities differ from the
standalone runtime API's defaults. A budget breach exits 2 with a diagnostic;
it is not a truncated successful run.

Compiler/run deadlines accept CLI overrides of 1–86,400 seconds. They include
process launch and wait, but cannot promise hard real-time cleanup under kernel
or scheduler stalls. The native adapter owns a process group, escalates graceful
termination, and reaps its direct child. Descendants that detach or change
credentials are outside that group guarantee. This is not per-case process
isolation or a security sandbox. See [process contract](../src/platform/PROCESS.md).

## Verification boundaries

The repository's generated runner executes mirrored units and independent
integration suites. Supporting modules and standalone oracles live outside
scanned roots in `test_support/`; invalid source is inert fixture data.

A separate Ruby parent compares lexical source inventory, CLI listing, and
actual PASS rows, then injects failures into disposable copies and checks exact
statuses and diagnostics. Independent matrices cover legacy and configured
discovery, both profiles, target/native isolation, ownership, lifecycle, process
cancellation, and finite boundaries. Silly and Promptnook adoption fixtures use
recorded source snapshots; they do not mutate or require those application
checkouts. Parent-owned temporary directories and bounded process waits keep
verification artifacts separate from authored source. See the
[external verification matrix](../integration/fixtures/README.md).

The [goosefmt consumer](adopting_goosefmt.md) demonstrates a public package
boundary. [Silly adoption](adopting_silly.md) keeps URL/HTTP suites in subsystem
paths with an optional native target. [Promptnook adoption](adopting_promptnook.md)
separates deterministic domain cases from a disposable native target. These
fixtures prove framework boundaries, not full consumer migrations or database
parity.
