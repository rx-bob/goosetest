"""Independent process/read-only checks. Supply built CLI and Goose oracle paths."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cli, oracle = (str(Path(p).resolve()) for p in sys.argv[1:])
repo = Path(__file__).resolve().parents[3]


def snapshot(root):
    result = {}
    for path in [root, *sorted(root.rglob("*"))]:
        info = path.lstat()
        digest = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        result[str(path.relative_to(root))] = (info.st_mode, info.st_size, info.st_mtime_ns, digest)
    return result


def run(args, cwd, status=0, contains=None):
    result = subprocess.run([cli, *args], cwd=cwd, capture_output=True, timeout=15)
    assert result.returncode == status, (args, result.returncode, result.stderr)
    if status == 0:
        assert result.stderr == b"", result.stderr
    else:
        assert result.stdout == b"", result.stdout
        assert result.stderr, args
    if contains:
        assert contains in result.stdout + result.stderr, (args, result.stdout, result.stderr)
    return result


def exact(result, expected, work):
    (work / "actual").write_bytes(result.stdout)
    (work / "expected").write_bytes(expected)
    subprocess.run([oracle, str(work / "actual"), str(work / "expected"),
                    str(result.returncode), "0"], check=True, timeout=15)


with tempfile.TemporaryDirectory(prefix="goosetest-cli-") as temporary:
    work = Path(temporary)
    project = work / "project with spaces"
    for name in ("src", "test", "integration"):
        (project / name).mkdir(parents=True)
    # Deliberately uncompilable source proves discovery does not invoke compilation.
    (project / "src/a.goose").write_text("not valid Goose production source")
    (project / "test/a_test.goose").write_text(
        'namespace a;\n// @Disabled("why\\n\\0")\n'
        'fn test_a(t: goosetest::Test&) { write_file("executed", "bad"); }\n')
    (project / "integration/flow_test.goose").write_text(
        'namespace flow;\nimport src.a;\nfn test_flow(t: goosetest::Test&) { write_file("executed", "bad"); }\n')
    before = snapshot(project)
    first = run(["list", "--project", str(project)], work)
    exact(first, b'integration  integration/flow_test.goose::flow::test_flow  '
          b'(integration/flow_test.goose:3:1)\n'
          b'unit  test/a_test.goose::a::test_a  (test/a_test.goose:3:1)\n'
          b'      disabled: why\\x0A\\x00\n'
          b'2 discovered cases: 1 executable, 1 disabled\n', work)
    assert first.stdout == run(["list"], project).stdout
    assert first.stdout == run(["--project", str(project), "list"], work).stdout
    audit = run(["check-mirror"], project)
    exact(audit, b'MIRROR OK  src/a.goose -> test/a_test.goose\n'
          b'Unit mirrors: 1 matched, 0 missing, 0 orphaned; 0 bad test filenames\n'
          b'Integration suites: 1\n', work)
    assert snapshot(project) == before
    for args in ([], ["unknown"], ["list", "--filter", "a"], ["list", "--project"],
                 ["list", "--project", ""], ["list", "extra"], ["list", "check-mirror"],
                 ["list", "--project", ".", "--project", "."], ["--help", "--bad"]):
        run(args, work, 2, b"Usage:")
    run(["--help"], work, contains=b"Default finite limits")
    run(["list", "--help", "--project", "nonexistent"], work, contains=b"Usage:")
    run(["list", "--project", "nonexistent"], work, 2, b"cannot open project")
    (project / "src/a.goose").rename(project / "src/renamed.goose")
    before = snapshot(project)
    for command in ("list", "check-mirror"):
        result = run([command], project, 2, b"MISSING TEST  src/renamed.goose")
        assert b"ORPHAN TEST  test/a_test.goose" in result.stderr
    assert snapshot(project) == before
    (project / "src/renamed.goose").rename(project / "src/a.goose")
    for content, error in (("namespace a;", b"requires at least one valid test"),
                           ('namespace a;\n// @Tag("x")\nfn test_a(t: goosetest::Test&) {}',
                            b"unsupported annotation")):
        (project / "test/a_test.goose").write_text(content)
        before = snapshot(project)
        for command in ("list", "check-mirror"):
            run([command], project, 2, error)
        assert snapshot(project) == before
    (project / "test/a_test.goose").rename(project / "test/helper.goose")
    run(["list"], project, 2, b"BAD TEST NAME  test/helper.goose")
    (project / "test/helper.goose").rename(project / "test/a_test.goose")
    (project / "test/a_test.goose").write_text('namespace a; fn test_a(t: goosetest::Test&) {}')
    assert os.geteuid() != 0, "permission-denial fixture requires an unprivileged user"
    unreadable = project / "src/a.goose"
    unreadable.chmod(0)
    try:
        run(["list"], project, 2, b"cannot read regular source file")
    finally:
        unreadable.chmod(0o644)
    unreadable.write_bytes(b"x" * 1048577)
    run(["check-mirror"], project, 2, b"max_file_bytes exceeded")
    # Missing roots and empty projects fail; the real example passes from another cwd.
    empty = work / "empty"
    empty.mkdir()
    run(["list", "--project", str(empty)], work, 2, b"required root is missing")
    (empty / "src").mkdir()
    (empty / "test").mkdir()
    run(["check-mirror", "--project", str(empty)], work, 2, b"no test cases discovered")
    example = repo / "examples/basic"
    before = snapshot(example)
    run(["list", "--project", str(example)], work, contains=b"3 discovered cases")
    run(["check-mirror", "--project", str(example)], work, contains=b"1 matched")
    assert snapshot(example) == before
print("cli process tests passed")
