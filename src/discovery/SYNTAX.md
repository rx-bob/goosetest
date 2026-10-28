# Test declaration scanning

`discover(manifest, inventory)` consumes a successful source inventory and scans
its admitted test files. Legacy inventories use `*_test.goose` under
`test/` and `integration/`, and reject other Goose files under those roots.
Configured inventories select `*_test.goose` from declared roots; ordinary
helpers remain importable but are not parsed as suites. Exclusions have already
been applied by inventory. Every discovered suite needs a valid test declaration
(disabled cases count). [MIRRORS.md](MIRRORS.md) documents full-project
validation. The syntax layer needs no native adapter.

## Authoring subset

Each scanned file requires one unqualified namespace before declarations; imports
may precede it. Top-level `test_*` functions accept `(t: goosetest::Test&)` or
`(t: goosetest::Test&, f: Fixture&)`. Parameter names do not affect identity.
Multiline signatures, ordinary comments and trailing parameter commas are accepted.
Only an optional single `inline` modifier is allowed. Generic, recursive, thread,
foreign and qualified tests fail, as do return types and forward declarations.

A file may declare one local nongeneric `struct Fixture`, before or after tests.
Any fixture parameter requires that declaration. Each hook may appear once:

| Hook | Parameters |
| --- | --- |
| `before_each`, `after_each` | `Fixture&`, or `goosetest::Test&` then `Fixture&` |
| `before_all`, `after_all` | none, or `goosetest::Test&` |

The compiler remains responsible for body semantics and unrelated declarations.

Standalone line comments immediately before a test may contain
`@DisplayName("label")` and `@Disabled("reason")`. Each may appear once; disabled
reasons must be nonempty. Ordinary documentation lines may share the contiguous
comment block. A blank line or block comment breaks attachment. Metadata attached
to a helper/hook, stranded at EOF, placed inside a test signature, or interleaved
with modifiers fails explicitly. Unknown annotations, tags, repetition annotations,
extra arguments, raw-string arguments and malformed escapes fail. An `@` inside
ordinary prose is not an annotation. Body comments are ignored by discovery.

## Lexing and identity

The lexer recognizes identifiers, escaped quoted strings, byte characters,
triple-quoted raw strings, line comments, nested block comments and balanced
`()[]{}` groups. It accepts the pinned compiler's ordinary and hexadecimal byte
escapes. Ordinary quoted literals cannot span physical lines. A character must
decode to exactly one byte. BOM and CRLF are supported; locations are one-based
lines and byte columns. Literal/comment bodies cannot create declarations.
Matched delimiter indices skip nested bodies without recursion. Each scanning
loop advances or reports an error.

Legacy case identity is `<relative path>::<namespace>::<function>`. Configured
identity prefixes the selected target:
`<target>::<relative path>::<namespace>::<function>`. Display names and parameter
names never change identity. Duplicate IDs and suite namespaces fail before
completion, regardless of case filter. Case order follows sorted target, inventory
path, and declaration order. Duplicate detection sorts temporary indices once; it
does not reorder the manifest or perform all-pairs comparisons.

## Ownership, limits and diagnostics

The caller supplies initially empty growable `Suite`, `Case`, text-byte and
error-path arrays to `new_manifest`. Keep these owners alive while using the
manifest. Paths, namespaces, names, IDs and decoded annotations are copied into
the text arena; no token or source-buffer references survive parsing. Suites retain
root kind and inventory index, fixture/hook locations, and contiguous case ranges.
Use `manifest_text` to resolve a span.

`parse_file` supports source-only callers. Call `finish_manifest` after all files;
`discover` does this automatically. Treat each context as single-use.
`manifest_status` is 0 only after successful completion, otherwise 2. Partial
records on failure are diagnostic data, not an executable manifest. The first
error retains its typed issue, path and location; `manifest_error_text` renders
`path:line:column: message` without printing anything itself.

| Syntax limit | Default | Scope |
| --- | ---: | --- |
| `max_file_bytes` | 1048576 | Each scanned file |
| `max_total_bytes` | 67108864 | Sum of scanned test-file bytes |
| `max_tokens` | 262144 | Each file, including comments |
| `max_nesting` | 128 | Delimiters plus nested block comments |
| `max_suites` | 4096 | Manifest suites |
| `max_cases` | 65536 | Manifest cases |
| `max_text_bytes` | 8388608 | Retained metadata bytes |

All limits are injectable and nonnegative; zero is valid and exact bounds succeed.
Lexing retains one bounded file token buffer and delimiter stack at a time.
Metadata decoding scratch is bounded by source size. Error paths are separate so
exhausting the metadata arena cannot erase diagnostic provenance. Filesystem
inventory limits apply independently before syntax scanning.

## Verification

From the repository root with Goose v2026.3, choose a temporary cache/output path:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project . --filter test/discovery/
goosefmt check --config .goosefmt.toml src/discovery test/discovery test_support/syntax.goose
```

Expected: selected discovered tests pass and exit 0. Independent builtin assertions cover
lexical decoys, multiline authoring, hook forms, unsupported declarations,
annotation attachment/escapes, stable IDs, duplicates, temporary source ownership,
inventory filtering, exact/over budgets and path/line/column diagnostics. The
representative authoring fixture is `.goose.data` so filesystem discovery does not
mistake it for a real integration suite.
