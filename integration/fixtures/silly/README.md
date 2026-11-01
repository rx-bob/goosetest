# Silly URL and HTTP adoption fixture

This independent fixture preserves Silly's standalone URL and HTTP host checks,
then runs converted goosetest cases from the existing `tests/request` and
`tests/http` paths. It materializes the bounded source closure from the recorded
snapshots; it does not require `/Users/bob/repos/silly` or modify that checkout.

The source snapshots are untracked working-tree files from the Silly checkout at
the recorded HEAD. `provenance.json` records their SHA-256 hashes and says that
HEAD is context only. The verifier checks every snapshot and the copied production
files before it exits.

The configured `core` target uses mirror policy `off`, so no artificial production
mirror modules or empty test roots are added. `check-mirror` reports that policy
as disabled. A separate `optional_native` target names an unavailable native
source; the URL/HTTP target passes without it, while selecting that target exits
2 at compilation.

## Preserved behavior

The original URL suite covers strict and literal malformed escapes, `%2F` and
single-pass decoding, query plus handling, UTF-8 and NUL bytes, zero/exact output
capacity, and unchanged output after failure. HTTP checks cover valid and invalid
host authorities and request-target syntax. Converted cases preserve these inputs
and expectations while adding framework case identities and failure diagnostics.

The passing core inventory is exactly:

```text
core::tests/http/http_host_test.goose::http_host_test::test_invalid_authority_forms
core::tests/http/http_host_test.goose::http_host_test::test_request_target_syntax
core::tests/http/http_host_test.goose::http_host_test::test_valid_authority_forms
core::tests/request/url_test.goose::url_test::test_literal_invalid_escapes
core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity
core::tests/request/url_test.goose::url_test::test_strict_query_decoding
```

The verifier runs original and converted checks in both profiles, checks these
exact IDs, mutates one expected path value and requires status 1 with expected
and actual output, and selects the optional native target to require status 2.

## Reproduce

From the goosetest repository root:

```sh
task build
ruby integration/fixtures/silly/verify.rb build/goosetest
```

The independent fixture is included in `task test` through
`integration/fixtures/verify.rb`.
