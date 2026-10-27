# Adopting goosetest in pretty-goose

The [isolated consumer fixture](../integration/fixtures/pretty_goose/README.md)
shows how representative pretty-goose behavior maps to generated tests. It copies
six production modules unchanged into a disposable package, runs selected original
checks with builtin assertions, then runs equivalent checks through goosetest.
It does not migrate or change the original pretty-goose repository.

## Scope and source provenance

The source snapshot comes from the local pretty-goose working tree inspected on
2026-10-27. Its HEAD was `1165aa2dbdf2d3f221d6f4758b3fc1b7bb596fec`, but that commit
tracked only `.gitignore`: the formatter, lexer, and test sources were untracked.
The commit therefore does not identify the copied implementation. The fixture's
[provenance manifest](../integration/fixtures/pretty_goose/provenance.json) records
source hashes; the copied bytes are the reproducible reference.

No repository remote or license file was present in the inspected tree. This
example records that fact without asserting a published upstream revision or
assigning a license to those files. It needs no installed pretty-goose checkout,
and it does not fetch code or reference a developer's absolute source path at run
time.

The six-module dependency closure is `lexer`, `lexer_scan`, `formatter`,
`formatter_rules`, `formatter_imports`, and `formatter_import_rules`. It excludes
the CLI, configuration loader, and linter. The selected original checks are
`src/tests.goose::test_statement_blocks` and `test_literal_preservation`; their
baseline retains builtin assertion checks for expected formatting, idempotence,
and token preservation. Inputs include strings containing punctuation, an escaped
character literal, nested block comments, and an exponent-form number.

## What the fixture demonstrates

The consumer has two small adapters, `src/lexer.goose` and `src/formatter.goose`,
with strict mirrors in `test/`. A separate `integration/pipeline_test.goose`
combines formatting and tokenization. The adapters expose the unchanged package
implementation; they are not copies or rewrites of its algorithms.

The disposable vendor package has an ordinary package entry module. Its original
sibling imports keep their meaning within that package. The consumer's authored
`goosetest_root.goose` explicitly declares both package locations and imports the
generated runner. Tests import their own dependencies and accept
`goosetest::Test&`. Assertion arguments are expected-first, and custom messages
identify the behavior being compared. No native test-root sidecar is needed for
this pure consumer.

The external verifier compares the original baseline and converted checks, then
changes one formatter expectation in a separate negative variant. That variant
must return exactly 1 with useful expected/actual diagnostics. The passing
consumer must discover and report the exact two unit IDs and one integration ID.
The parent owns the temporary project, vendor package, cache, and output files.

## A future migration of the real repository

The real tree currently runs `goose run src/tests.goose` through `task test`, and
its CLI entry is `src/goosefmt.goose`. Those files and commands remain unchanged
by this example. A full migration would require deliberate changes there:

1. Add a root CLI entry that imports implementation modules under `src/`. Keep
   executable-only wiring outside the production mirror inventory, and add a
   separate root `goosetest_root.goose` with explicit package declarations.
2. Decide the package root before changing imports. Existing bare imports such
   as `import lexer;` work with the current source-root layout. Preserve that
   package boundary or update project imports consistently to `src.*` when the
   root moves. Moving the entry alone does not repair those paths.
3. Split behavioral cases out of `src/tests.goose` into namespaced mirrored unit
   files. Move reusable test helpers to `test_support/`; put cross-module behavior
   in `integration/`. Replace manual calls from the test entry with discovery.
4. Provide a meaningful `test/<module>_test.goose` for every remaining production
   module under `src/`, including the configuration and linter modules omitted
   from this small fixture. The two adapter mirrors here demonstrate adoption at
   a package boundary; they do not establish full coverage of the original tree.
5. Review the real repository's build, run, install, and test tasks together before
   adopting the new entries. Preserve the original commands until that migration
   is explicitly undertaken and verified.

## Reproduce the isolated checks

Run these commands from the goosetest repository, with its documented compiler
and native build prerequisites:

```sh
task build
python3 integration/fixtures/pretty_goose/verify.py build/goosetest
```

The canonical independent verification command also includes the consumer matrix:

```sh
task test
```

All compiler invocations for this fixture use the supported debug path. The
verifier materializes `.goose.data` inputs only inside owned temporary directories;
the snapshots are fixture data, not discovered framework tests. No pretty-goose
test command is invoked in the original repository.
