"""Independent artifact ownership, recovery, and concurrent invocation checks."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]


def snapshot(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        info = path.lstat()
        data = path.read_bytes() if path.is_file() and not path.is_symlink() else None
        result[str(path.relative_to(directory))] = (info.st_mode, info.st_mtime_ns, data)
    return result


with tempfile.TemporaryDirectory(prefix="goosetest-artifacts-") as tmp:
    work = Path(tmp)
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))

    def source(root, names):
        body = '\n'.join(f'fn test_{name}(t: goosetest::Test&) {{ '
                         f't.assert_true(write_file("executed", "{name}")); }}' for name in names)
        (root / "test/a_test.goose").write_text(
            'namespace a_test;\nimport goosetest;\nimport os;\n' + body + '\n')

    def project(name, names=("first",)):
        root = work / (name + " with spaces")
        (root / "src").mkdir(parents=True)
        (root / "test").mkdir()
        (root / "src/a.goose").write_text("namespace a;\n")
        source(root, names)
        (root / "goosetest_root.goose").write_text(
            f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
            'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
        return root

    def run(root, status=0, contains=b"", extra=()):
        result = subprocess.run([cli, "test", "--project", str(root), *extra], cwd=work,
                                env=env, capture_output=True, timeout=120)
        assert result.returncode == status, (root.name, result.returncode, result.stdout, result.stderr)
        assert contains in result.stdout + result.stderr, (root.name, contains, result.stdout, result.stderr)
        return result

    repeated = project("repeat", ("one", "two", "three"))
    authored = (repeated / "goosetest_root.goose").read_bytes()
    run(repeated, contains=b"3 passed")
    generated = repeated / "goosetest_generated"
    first = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in generated.glob("*.goose")}
    manifest_before = ((generated / ".manifest").read_bytes(), (generated / ".manifest").stat().st_mtime_ns)
    run(repeated, contains=b"3 passed")
    assert first == {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in generated.glob("*.goose")}
    assert manifest_before == ((generated / ".manifest").read_bytes(), (generated / ".manifest").stat().st_mtime_ns)
    assert (repeated / "goosetest_root.goose").read_bytes() == authored
    # Extra user files are never removed, even when obsolete generated cases are pruned.
    (generated / "user-notes.txt").write_text("preserve me")
    source(repeated, ("renamed",))
    result = run(repeated, contains=b"1 passed")
    assert b"test_renamed" in result.stdout and b"test_three" not in result.stdout
    assert not (generated / "case_1.goose").exists()
    assert not (generated / "case_2.goose").exists()
    assert not (generated / "dispatch_0_0.goose").exists()
    assert (generated / "user-notes.txt").read_text() == "preserve me"
    assert b"test_three" not in b"".join(p.read_bytes() for p in generated.glob("*.goose"))
    assert (repeated / "goosetest_root.goose").read_bytes() == authored

    unowned = project("unowned")
    output = unowned / "goosetest_generated"
    output.mkdir()
    (output / "runner.goose").write_text("user source")
    before = snapshot(output)
    run(unowned, 2, b"artifacts")
    assert snapshot(output) == before and not (unowned / "executed").exists()

    # Replace an owned generated file with a link: target and link must survive unchanged.
    outside = work / "outside.goose"
    outside.write_text("untouchable")
    wrapper = generated / "case_0.goose"
    wrapper.unlink()
    wrapper.symlink_to(outside)
    (repeated / "executed").unlink()
    run(repeated, 2, b"artifact")
    assert wrapper.is_symlink() and outside.read_text() == "untouchable"
    assert not (repeated / "executed").exists()
    wrapper.unlink()
    run(repeated)

    # A changed wrapper cannot publish into a read-only directory or execute its stale binary.
    assert os.geteuid() != 0, "permission fixture requires an unprivileged user"
    source(repeated, ("changed",))
    (repeated / "executed").unlink()
    before_source = (generated / "case_0.goose").read_bytes()
    generated.chmod(0o500)
    try:
        run(repeated, 2, b"artifact")
        assert not (repeated / "executed").exists()
        assert (generated / "case_0.goose").read_bytes() == before_source
    finally:
        generated.chmod(0o700)
    run(repeated, contains=b"test_changed")

    # Simulate interruption after union manifest publication and a partial source update.
    manifest = generated / ".manifest"
    owned = set(manifest.read_text().splitlines())
    owned.add("case_999.goose")
    manifest.write_text(''.join(name + '\n' for name in sorted(owned)))
    (generated / "case_999.goose").write_text("interrupted obsolete module")
    (generated / "case_0.goose").write_text("interrupted current module")
    (generated / ".write-tmp").write_text("interrupted atomic write")
    run(repeated, contains=b"test_changed")
    assert not (generated / "case_999.goose").exists()
    assert not (generated / ".write-tmp").exists()
    assert "case_999.goose" not in manifest.read_text()
    assert (generated / "user-notes.txt").read_text() == "preserve me"

    # New generated names cannot claim an existing unmanifested user file.
    (generated / "case_1.goose").write_text("user-owned future name")
    source(repeated, ("changed", "added"))
    (repeated / "executed").unlink()
    run(repeated, 2, b"artifact")
    assert (generated / "case_1.goose").read_text() == "user-owned future name"
    assert not (repeated / "executed").exists()
    (generated / "case_1.goose").unlink()
    run(repeated, contains=b"2 passed")
    (repeated / "src/a.goose").rename(repeated / "src/b.goose")
    (repeated / "test/a_test.goose").rename(repeated / "test/b_test.goose")
    result = run(repeated, contains=b"test/b_test.goose")
    assert b"test/a_test.goose" not in result.stdout
    assert (repeated / "goosetest_root.goose").read_bytes() == authored

    compiler = work / "slow compiler"
    fixture = Path(__file__).resolve().parents[1] / "execution/process_tree.c"
    compiler_source = work / "compiler.c"
    compiler_source.write_text('#include "' + str(fixture) + '"\n'
                               'int main(void) { gt_pipeline_wait(); return 0; }\n')
    subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", str(compiler_source),
                    "-o", str(compiler)], check=True, timeout=30)

    def owned_tree():
        ready = concurrent / "owned-pids"
        if not ready.exists():
            return []
        values = ready.read_text().split()
        return [int(value) for value in values] if len(values) == 2 else []

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
    concurrent = project("concurrent")
    proc = subprocess.Popen([cli, "test", "--project", str(concurrent), "--compiler", str(compiler)],
                            cwd=work, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pids = []
    try:
        until = time.monotonic() + 15
        while not pids:
            pids = owned_tree()
            assert proc.poll() is None, proc.communicate()
            assert time.monotonic() < until, "compiler process tree never became ready"
            time.sleep(.02)
        before = snapshot(concurrent / "goosetest_generated")
        run(concurrent, 2, b"artifact")
        assert snapshot(concurrent / "goosetest_generated") == before
        proc.send_signal(signal.SIGINT)
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 130, (proc.returncode, stdout, stderr)
        assert b"compilation failed;" in stderr and b"signal=2" in stderr, stderr
        until = time.monotonic() + 5
        while not all(stopped(pid, index > 0) for index, pid in enumerate(pids)) and time.monotonic() < until:
            time.sleep(.02)
        assert all(stopped(pid, index > 0) for index, pid in enumerate(pids)), pids
        assert not (concurrent / "executed").exists(), "stale executable ran"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=5)
        for pid in pids or owned_tree():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    # Cancellation releases ownership; every retry regenerates and rebuilds.
    run(concurrent, contains=b"1 passed")
    assert (concurrent / "executed").exists()
print("artifact ownership matrix passed")
