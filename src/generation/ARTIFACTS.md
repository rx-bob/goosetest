# Owned generated artifacts

`artifacts::publish` joins bounded generation with the CLI-only native staging
boundary. The importable assertion runtime has no artifact or native dependency.

The authored configured entry, or legacy `goosetest_root.goose`, is checked as a
regular file, never written.
The generated directory must be new or carry the exact `.owner` version marker
and valid bounded `.manifest`. Preexisting unowned directories are not adopted.
A nonblocking directory lock is held through build, run, and child cleanup;
conflicts return status 2. The descriptor releases the lock on close.

Publication first persists the union of previous and desired filenames. This
records partial writes for recovery after interruption. Each source is written
to an internal temporary file and atomically renamed; byte-identical content is
left untouched. Dependencies precede `runner.goose`. Finalization removes only
obsolete names in the manifest and then publishes the desired manifest. Unknown
files are preserved, and a newly generated name colliding with an unlisted file
fails. No recursive deletion or user-root rewriting occurs.

`tests` and `completion` are reserved, manifest-owned execution outputs. In a
configured target they are stored inside its owned subdirectory. Both are
removed before compilation, so successful old runs cannot supply new execution
or completion evidence. Any publication/reset error prevents compilation;
compiler failure prevents execution. Generated sources remain after failures.

Legacy generated modules and execution outputs live directly in
`goosetest_generated/`. Configured targets keep their modules, binary output and
completion record under `goosetest_generated/<target>/`; each target's compiler
cache is separately partitioned by profile. The authored entry and its adjacent
`goosetest_<target>.build` remain consumer-owned. Selecting another target does
not rewrite or claim either file.

`cache` is reserved against target names and generated module paths. The default
compiler caches live below `goosetest_generated/cache/<target-or-default>/<profile>`;
they are outside the source manifest and are never pruned by generation. Compiler
caches are not test-result caches: each invocation rebuilds its binary.

Internal metadata and temporary filenames are reserved by the ownership marker.
Malformed manifests and symlinks fail closed. Ownership is an application safety
contract, not a sandbox against project code deliberately editing its metadata.

Verification:

```sh
python3 integration/fixtures/artifacts/verify.py /tmp/goosetest
```

The independent verifier checks repeatability and mtimes, obsolete files,
unowned paths, failed writes, interrupted publication, concurrent invocation,
cancellation/retry, and stale executable prevention. Native boundary checks live
beside it in `native_test.c`.

The marker is exactly `goosetest artifacts v1\n`. A missing manifest beneath a
valid marker means empty ownership, allowing interruption during initialization
to recover; it does not authorize replacement of existing source files. The
manifest stores sorted, newline-delimited generated paths, at most 8 MiB and
140004 names (the old/new union). Names are at most `NAME_MAX` bytes, use lowercase
ASCII letters, digits, underscores or dots, with at most one target-directory
separator. Files are `.goose` modules or the two reserved execution outputs.
Target subdirectories carry a checked owner marker. Duplicates, malformed names,
symlinks and hardlinks
are rejected. Source writes are limited to 65536 bytes each. The reserved
`.write-tmp` file is recovered only after marker validation and exclusive locking.
A brief project-directory lock serializes initial directory creation; the output
directory lock remains held throughout the invocation.

Run the native contract harness with a parent-owned empty temporary directory:

```sh
clang -Wall -Wextra -Werror native/staging.c native/staging_manifest.c \
    integration/fixtures/artifacts/native_test.c -o /tmp/goosetest-artifacts-native
python3 - <<'PY'
import subprocess
import tempfile
with tempfile.TemporaryDirectory(prefix="goosetest-native-artifacts-") as project:
    subprocess.run(["/tmp/goosetest-artifacts-native", project], check=True)
PY
```

It checks lock contention/release, preparation before writes, unchanged inode and
mtime, interrupted union and temporary-file recovery, pruning, completion/reset,
user-file collisions, malformed/duplicate/oversized manifests, and link refusal.
