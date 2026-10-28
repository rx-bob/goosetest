"""External shell-status oracle for the one-command execution pipeline."""
import os
from pathlib import Path
import signal
import shutil
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
    bad = project("audit")
    (bad / "src/missing.goose").write_text("namespace missing;\n")
    run(bad, 2, b"no tests executed")
    assert not (bad / "goosetest_generated").exists()
    empty = project("empty")
    (empty / "test/a_test.goose").unlink()
    (empty / "src/a.goose").unlink()
    run(empty, 2, b"no tests executed")
    oversized = project("generation")
    text = (oversized / "test/a_test.goose").read_text().replace(
        "fn test_first", '// @DisplayName("' + 'x' * 1025 + '")\nfn test_first')
    (oversized / "test/a_test.goose").write_text(text)
    run(oversized, 2, b"generation")
    assert not (oversized / "goosetest_generated").exists()
    for profile in ("debug", "optimized"):
        run(project("missing compiler " + profile), 2, b"compilation",
            ("--profile", profile, "--compiler", str(work / "absent")))
    # The compiler and runner each own a separately observed hostile process tree.
    # A finite native alarm also bounds the fixture if both framework and verifier fail.
    fixture = Path(__file__).with_name("process_tree.c")
    compiler_source = work / "compiler.c"
    compiler_source.write_text('#include "' + str(fixture) + '"\n'
                               'int main(void) { gt_pipeline_wait(); return 0; }\n')
    compiler = work / "compiler with spaces"
    subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", str(compiler_source),
                    "-o", str(compiler)], check=True, timeout=30)

    def stopped(pid, allow_zombie=False):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        if not allow_zombie:
            return False
        state = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="],
                               capture_output=True, text=True, timeout=3).stdout.strip()
        return not state or state.startswith("Z")

    def owned_tree(root):
        ready = root / "owned-pids"
        if not ready.exists():
            return []
        values = ready.read_text().split()
        return [int(value) for value in values] if len(values) == 2 else []

    def interruption(stage, cancel, profile):
        root = project(stage + " " + profile + (" cancellation" if cancel else " timeout"),
                       't.assert_true(write_file("executed", "fresh"));')
        profile_args = ["--profile", profile]
        # Seed a prior executable; no interruption may execute that stale artifact.
        run(root, 0, extra=profile_args)
        (root / "executed").unlink()
        extra = []
        if stage == "compilation":
            extra = [*profile_args, "--compiler", str(compiler), "--compile-timeout-seconds",
                     "1" if not cancel else "30"]
        else:
            shutil.copyfile(fixture, root / "process_tree.c")
            (root / "goosetest_root.build").write_text('c_sources = ["process_tree.c"];\n')
            (root / "test/a_test.goose").write_text(
                'namespace a_test;\nimport goosetest;\n'
                'extern "gt_pipeline_wait" fn wait_tree();\n'
                'fn test_first(t: goosetest::Test&) { wait_tree(); }\n')
            extra = [*profile_args, "--run-timeout-seconds", "1" if not cancel else "30"]
        proc = subprocess.Popen([cli, "test", "--project", str(root), *extra],
                                cwd=work, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pids = []
        try:
            until = time.monotonic() + 20
            while not pids:
                pids = owned_tree(root)
                assert proc.poll() is None, proc.communicate()
                assert time.monotonic() < until, "process tree never became ready"
                time.sleep(.02)
            if cancel:
                proc.send_signal(signal.SIGINT)
            stdout, stderr = proc.communicate(timeout=15)
            assert proc.returncode == (130 if cancel else 2), (proc.returncode, stdout, stderr)
            diagnostic = stage.encode() + (b" failed;" if cancel else b" exceeded its deadline")
            assert diagnostic in stderr, (diagnostic, stdout, stderr)
            if cancel:
                assert b"signal=2" in stderr and b"run incomplete" in stderr, stderr
            assert not (root / "executed").exists(), "stale executable ran"
            until = time.monotonic() + 5
            while not all(stopped(pid, index > 0) for index, pid in enumerate(pids)) and time.monotonic() < until:
                time.sleep(.02)
            assert all(stopped(pid, index > 0) for index, pid in enumerate(pids)), ("owned process survived", pids)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=5)
            for pid in pids or owned_tree(root):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        (root / "test/a_test.goose").write_text(
            'namespace a_test;\nimport goosetest;\nimport os;\n'
            'fn test_first(t: goosetest::Test&) { t.assert_true(write_file("executed", "fresh")); }\n')
        run(root, 0, b"1 passed", profile_args)
        assert (root / "executed").read_text() == "fresh", "ownership was not reusable"

    for profile in ("debug", "optimized"):
        for cancel in (False, True):
            interruption("compilation", cancel, profile)
    for cancel in (False, True):
        interruption("execution", cancel, "debug")
    # A compiler claiming success without producing output must never succeed.
    compiler.write_text("#!/bin/sh\nexit 0\n")
    run(project("no binary"), 2, b"execution", ("--compiler", str(compiler)))
print("execution matrix passed")
