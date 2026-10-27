"""External shell-status and plain-text oracle for the handwritten reporting harness."""
from pathlib import Path
import subprocess
import sys

harness = str(Path(sys.argv[1]).resolve())


def run(mode, status, summary):
    result = subprocess.run([harness, mode], capture_output=True, timeout=15)
    assert result.returncode == status, (mode, result.returncode, result.stdout, result.stderr)
    assert result.stderr == b"", result.stderr
    assert summary in result.stdout, result.stdout
    assert b"locations identify test declarations" in result.stdout
    assert all(byte == 10 or 32 <= byte <= 126 for byte in result.stdout), result.stdout
    repeated = subprocess.run([harness, mode], capture_output=True, timeout=15)
    assert (repeated.returncode, repeated.stdout, repeated.stderr) == (status, result.stdout, result.stderr)
    return result.stdout


passed = run("passing", 0, b"Cases: 5 passed, 0 failed, 1 skipped, 0 errors, 0 not run")
assert b"viewer write access" in passed and b"pending clock support" in passed
assert b"Failures:" not in passed
failed = run("failing", 1, b"Cases: 4 passed, 1 failed, 1 skipped, 0 errors, 0 not run")
assert b"Failures:" in failed
assert b"test/permissions_test.goose:30" in failed
assert b".allowed expected: <true> actual: <false>" in failed
assert b".reason expected: <ok> actual: <insufficient_role>" in failed
assert failed.index(b".allowed") < failed.index(b".reason")
assert b".role expected" not in failed
mixed = run("mixed", 1, b"Cases: 1 passed, 2 failed, 1 skipped, 0 errors, 2 not run; 2 filtered")
for phase in (b"setup", b"test", b"cleanup", b"suite setup", b"suite cleanup"):
    assert b"[" + phase + b"]" in mixed, (phase, mixed)
assert b"Suite-hook errors:" in mixed, mixed
assert b"Assertions: 6; suite-hook errors: 2" in mixed, mixed
assert b"setup\\x0Amessage" in mixed and b"body\\x1Bmessage" in mixed
assert b"cleanup\\x0Dmessage" in mixed and b"pending\\x0Areason\\x1B" in mixed
incomplete = run("incomplete", 2, b"Cases: 1 passed, 0 failed, 0 skipped, 0 errors, 3 not run")
assert b"incomplete run: diagnostic byte limit exhausted" in incomplete
print("reporting process tests passed")
