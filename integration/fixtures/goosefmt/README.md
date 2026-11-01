# Isolated goosefmt consumer

This fixture validates representative formatter and lexer adoption without
changing the original goosefmt checkout. It runs selected original tests with
builtin assertions, converts the same behavior to public goosetest tests, and
checks a deliberate failing formatter expectation from an independent parent.
See the [migration recipe](../../../docs/adopting_goosefmt.md) for the broader
repository changes that a real migration would require.

## Files and package boundaries

- `production/*.goose.data` holds six byte-for-byte production snapshots:
  `lexer`, `lexer_scan`, `formatter`, `formatter_rules`, `formatter_imports`, and
  `formatter_import_rules`. `production/original_tests.goose.data` separately
  records the original regression source used to verify baseline extraction.
- `baseline.goose.data` retains selected original test functions and their
  assertion helpers. The original checks are statement-block formatting and
  literal preservation from `src/tests.goose`.
- `consumer/src/` contains two small adapters, with matching unit suites in
  `consumer/test/`. `consumer/integration/pipeline_test.goose.data` checks the
  formatting/tokenization boundary. Shared authored checks live in
  `consumer/test_support/contracts.goose.data`.
- `provenance.json` records the snapshot hashes and source context.
- `verify.rb` materializes, builds, runs, and removes the disposable fixture.

The original implementation stays unchanged in a separate temporary vendor
package. A small package entry resolves its existing bare sibling imports. The
consumer root explicitly declares that package and goosetest, then imports the
generated runner. The adapter modules are the consumer's production mirror
boundary; this example does not claim to migrate every goosefmt module.
No developer-specific source directory is needed to run it.

## Independent expectations

The baseline uses builtin assertions independently of framework success reporting.
Converted checks use expected-first framework assertions and custom diagnostic
messages. They preserve the original expected formatting and token checks,
including punctuation inside strings, an escaped character literal, nested
comments, idempotence, and token text/kind preservation.

The passing consumer has these exact discovered and reported IDs:

```text
test/formatter_test.goose::consumer_formatter_test::test_statement_blocks
test/lexer_test.goose::consumer_lexer_test::test_literal_preservation
integration/pipeline_test.goose::consumer_pipeline_test::test_format_and_lex
```

The negative variant changes a formatter expectation and must exit 1, with the
case identity, custom message, and useful expected/actual values. It must not
count a compiler error or fatal runtime abort as an expected assertion failure.
The independent parent observes the process status and owns temporary resources.

## Reproduce

From the goosetest repository root:

```sh
task build
ruby integration/fixtures/goosefmt/verify.rb build/goosetest
```

`task test` includes this matrix alongside self-host and failure-contract checks.
It uses `goose build --debug`; no command runs inside the original goosefmt
checkout. Fixture `.goose.data` files are materialized as source only in the
owned temporary consumer, so they cannot be discovered as framework suites.

## Provenance

The inspected working tree had HEAD
`1165aa2dbdf2d3f221d6f4758b3fc1b7bb596fec`, but only `.gitignore` was tracked in that
commit. The production and test source files were untracked local work. The
manifest hashes identify the copied bytes; HEAD is context, not a source pin.
No remote or license file was present, and this fixture makes no additional
licensing claim. Neither the original working tree nor its existing Taskfile test
command was modified or executed for this demonstration.
