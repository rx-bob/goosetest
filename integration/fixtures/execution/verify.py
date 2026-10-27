"""External shell-status oracle for the one-command execution pipeline."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]

with tempfile.TemporaryDirectory(prefix="goosetest-execution-") as tmp:
    work = Path(tmp)
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))

    def project(name, body="t.assert_true(true);", second=""):
        root = work / (name + " with spaces")
        (root / "src").mkdir(parents=True)
        (root / "test").mkdir()
        (root / "src/a.goose").write_text("namespace a;\n")
        (root / "test/a_test.goose").write_text(
            "namespace a_test;\nimport goosetest;\nimport os;\n"
            "fn test_first(t: goosetest::Test&) { " + body + " }\n" + second)
        (root / "goosetest_root.goose").write_text(
            f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
            'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
        return root

    def run(root, status, contains=b"", extra=()):
        result = subprocess.run([cli, "test", "--project", str(root), *extra],
                                cwd=work, env=env, capture_output=True, timeout=120)
        assert result.returncode == status, (root.name, result.returncode, result.stdout, result.stderr)
        assert contains in result.stdout + result.stderr, (contains, result.stdout, result.stderr)
        return result

    good = project("passing", 'var value: u8[>..] = []; t.assert_true(read_file("resource", value)); '
                   't.assert_eq("hello", value);')
    (good / "resource").write_text("hello")
    run(good, 0, b"1 passed")
    # Broken new source must remove the previous executable before compilation.
    (good / "test/a_test.goose").write_text("namespace a_test;\nfn test_broken(t: goosetest::Test&) { missing(); }")
    run(good, 2, b"compilation")
    assert not (good / "goosetest_generated/tests").exists()
    failed = project("assertion", 't.assert_eq(1, 2); print("NEVER");',
                     'fn test_second(t: goosetest::Test&) { print("FOLLOWING"); }\n')
    result = run(failed, 1, b"FOLLOWING")
    assert b"NEVER" not in result.stdout
    run(project("compile", "unknown_function();"), 2, b"compilation")
    run(project("abort", "assert(false);"), 2, b"execution")
    for code in (0, 1, 7):
        run(project(f"exit{code}", f"exit({code});"), 2, b"incomplete")
    run(project("hang", "while true {}"), 2, b"execution exceeded its deadline",
        ("--run-timeout-seconds", "1"))
    bad = project("audit")
    (bad / "src/missing.goose").write_text("namespace missing;\n")
    run(bad, 2, b"no tests executed")
    assert not (bad / "goosetest_generated").exists()
    empty = project("empty")
    (empty / "test/a_test.goose").unlink()
    (empty / "src/a.goose").unlink()
    run(empty, 2, b"no tests executed")
    disabled = project("generation")
    text = (disabled / "test/a_test.goose").read_text().replace("fn test_first", '// @Disabled("later")\nfn test_first')
    (disabled / "test/a_test.goose").write_text(text)
    run(disabled, 2, b"generation")
    assert not (disabled / "goosetest_generated").exists()
    run(project("missing compiler"), 2, b"compilation", ("--compiler", str(work / "absent")))
    compiler = work / "compiler with spaces"
    compiler.write_text('#!/bin/sh\nprintf started > compiler-started\nsleep 30\n')
    compiler.chmod(0o755)
    timeout = project("compiler deadline")
    run(timeout, 2, b"compilation exceeded its deadline",
        ("--compiler", str(compiler), "--compile-timeout-seconds", "1"))
    assert (timeout / "compiler-started").exists()
    cancel = project("cancel")
    proc = subprocess.Popen([cli, "test", "--project", str(cancel), "--compiler", str(compiler)],
                            cwd=work, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        until = time.monotonic() + 15
        while not (cancel / "compiler-started").exists():
            assert time.monotonic() < until
            time.sleep(.02)
        proc.send_signal(signal.SIGINT)
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 130, (proc.returncode, stdout, stderr)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    # A compiler claiming success without producing output must never succeed.
    compiler.write_text("#!/bin/sh\nexit 0\n")
    run(project("no binary"), 2, b"execution", ("--compiler", str(compiler)))
print("execution matrix passed")
