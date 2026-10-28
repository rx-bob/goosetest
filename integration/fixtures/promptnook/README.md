# Promptnook-shaped adoption fixture

This standalone consumer keeps `users/`, `workspaces/`, and `db/` at project
root, with separate `tests/core` and `tests/database` targets. Its domain case
uses an unchanged snapshot of `workspaces::append_tree_json` and the small
`mcp_protocol::json_member_last` helper. Provenance identifies source revision,
line ranges, hashes, and the existing HTTP contract case that supplied the
ordered root/child/duplicate/stale-row shape. The SQL join excludes stale IDs
before the serializer receives rows; the pure fixture covers the remaining
ordered and nested output.

The fixture compiles core without its deliberately unavailable database link
input. Selecting database reports that missing source. Adding the tiny native
stand-in allows database tests to run twice; each fresh target process starts
its native counter at one, creates its owned marker under the disposable project,
and removes it in `after_each`. Separate target sidecars keep that native code
outside core's build closure.

The native stand-in proves target linkage and process isolation. It does not
implement libSQL, exercise Promptnook database calls, or establish application
business parity. The application HTTP baseline/candidate comparator remains a
separate gate.

Reproduce from the goosetest repository root:

```sh
task build
python3 integration/fixtures/promptnook/verify.py build/goosetest
```

The verifier builds a temporary project and never opens, migrates, resets, or
modifies the original Promptnook checkout or its default database.
