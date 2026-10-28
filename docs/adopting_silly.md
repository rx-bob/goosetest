# Adopting goosetest in Silly

The URL and HTTP fixture shows how Silly can keep subsystem suites at their
current paths while moving selected cases into one configured target. The
framework fixture is representative evidence, not a migration of the Silly
checkout. The existing Silly runner can adopt the target incrementally and keep
compiler, native, service, and external integration groups under their current
owners until each has a suitable target boundary.

## Migration ledger

Record every old standalone case or group as either a new stable goosetest ID or
an explicitly retained owner. The URL and host cases in the maintained fixture
map as follows:

| Existing Silly check | New goosetest ID | Disposition |
| --- | --- | --- |
| `url_test::strict` | `core::tests/request/url_test.goose::url_test::test_strict_query_decoding` | Converted |
| `url_test::literal` | `core::tests/request/url_test.goose::url_test::test_literal_invalid_escapes` | Converted |
| `url_test::path_and_limits` | `core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity` | Converted |
| `http_host_test::valid_hosts` | `core::tests/http/http_host_test.goose::http_host_test::test_valid_authority_forms` | Converted |
| `http_host_test::invalid_hosts` | `core::tests/http/http_host_test.goose::http_host_test::test_invalid_authority_forms` | Converted |
| `http_host_test::target_syntax` | `core::tests/http/http_host_test.goose::http_host_test::test_request_target_syntax` | Converted |
| Native, service, and broad integration executables | Their current Silly-owned commands | Retain until separately migrated |

Use the ledger to keep historical failures traceable. Do not rename or remove a
standalone executable until its checks have a new ID or an explicit retained
owner. The framework adoption does not require moving all 127 historical
executables at once.

## Running configured subsystem checks

Silly's existing runner can invoke goosetest once per compiler profile and then
continue with its retained groups:

```sh
goosetest test --project "$silly_root" --target core --profile debug
goosetest test --project "$silly_root" --target core --profile optimized
# Existing Silly-owned compiler, native, service, and external checks follow.
```

The target config can admit `tests/request` and `tests/http` directly and set
mirror policy to `off` while those source trees have no one-to-one test layout.
`check-mirror` then reports that mirror enforcement is disabled rather than
claiming module coverage. A target that later adopts a strict pair can enable
mirror checking independently.

Keep optional native libraries in a separate named target. Selecting `core`
should not inspect, compile, or link that dependency; selecting the native target
may report status 2 when the dependency is unavailable. Shared application
databases, deployed services, and HTTP comparison orchestration remain under the
existing Silly runner because process isolation does not reset their external
state.

The self-contained verifier and provenance ledger live in
[`integration/fixtures/silly`](../integration/fixtures/silly/README.md). It uses
source snapshots and does not depend on a developer-specific Silly checkout.
