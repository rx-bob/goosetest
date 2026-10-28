# Independent failure-contract verification

From the repository root, run the supported debug path:

```sh
goose build --debug scripts/verify.goose -o /tmp/goosetest-verify
/tmp/goosetest-verify
```

`python3 integration/fixtures/verify.py` invokes the same independent parent.
It builds the CLI and comparison oracle once, then runs the following matrices.
Every fixture checks the actual child process status and diagnostic text outside
Goose's assertion runtime. Python assertions are enabled explicitly for child
oracles. A nonzero oracle status fails the command.

| Matrix | Contract checked |
| --- | --- |
| `self_host` | Exact source/list/result inventory; injected assertion in a disposable repository copy exits 1. |
| `cli` | Missing mirrors, malformed/unsupported metadata, empty discovery, unreadable and oversized sources exit 2 before compilation or execution. |
| `execution` | Assertions exit 1 and later tests run; compile errors, fatal aborts, early exits, missing output and stage deadlines exit 2; SIGINT exits 130. No stale executable runs. |
| `artifacts` | Unowned files and symlinks survive; failed writes cannot execute stale output; concurrent ownership is exclusive and reusable after cancellation. |
| `limits` | 129 production/test pairs exceed 128 files in each root; one module has 65 cases, and all 321 case IDs match discovery, generated wrappers and passing rows exactly. Oversized input fails before compiler invocation. |
| `disabled` | Disabled assertions and hooks remain cold but compiler checked, with original skip reasons. |
| `selection` | Filters preserve compile checks, including cleanup hooks and non-local returns; empty selection exits 2; fail-fast still cleans up. |
| `pretty_goose` | Byte-preserved formatter/lexer baseline, two unit mirrors and one integration suite; changed formatter expectation exits 1 with value diagnostics. |
| `silly` | Byte-preserved URL/HTTP baseline and six target-qualified cases in debug/optimized profiles; optional native dependency stays outside core. |
| `promptnook` | Workspace-tree source snapshot, root-domain layout, unavailable database link isolation, fresh native state and owned resource cleanup. |
| `lifecycle`, `suite` | Setup/body/cleanup failure combinations preserve causes, continuation, cleanup and nonzero statuses. |

The compiler wrapper in `limits` also checks the real invocation begins with
`build --debug`. No release-mode or performance matrix is implied. Capacity
checks compare independently constructed identities and exact counts, never
elapsed-time targets.

The parent creates a temporary directory for caches, fixture roots and child
`TMPDIR`. Each oracle runs in its own process group with a 900-second deadline
and an 8 MiB output budget. The parent cleans its owned group on failure.
Interruptible stage fixtures independently record and clean their separate native
process groups; the hostile native fixture has a 30-second emergency alarm.
Compiler and runtime timeout/cancellation checks verify child termination and a
successful retry of the same project, proving that ownership locks were released.
See [execution details](execution/README.md).

Use an unprivileged user: permission-denial cases deliberately reject root rather
than silently skip. The supported baseline remains the pinned Goose compiler on
the repository's POSIX native platform, with Python 3, clang and goosefmt available.
Temporary names and recorded PIDs belong only to each fixture; no installed
binary or authored checkout source is replaced.

Valid discovered integration suites are `integration/*_test.goose`. Supporting
Goose modules live under `test_support/`. Intentionally invalid Goose text uses
`.goose.data` or is constructed inside a disposable consumer. It is never an
accidentally discovered or formatted suite.

See [pretty-goose adoption](pretty_goose/README.md) for the source snapshot,
public-package conversion, and migration recipe. Its recorded source-directory
path is provenance only; verification runs without that original checkout.
See [Silly adoption](silly/README.md) for the matching URL/HTTP consumer shape.
See [Promptnook-shaped adoption](promptnook/README.md) for the domain/native target boundary.
