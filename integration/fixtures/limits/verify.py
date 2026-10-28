"""Independent completeness oracle beyond 128 files per root and 64 cases per module."""
import ast
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]


def call(args, work, env, status=0):
    result = subprocess.run([cli, *args], cwd=work, env=env, capture_output=True, timeout=180)
    assert result.returncode == status, (args, result.returncode, result.stdout, result.stderr)
    return result


def wrapper_identity(path):
    source = path.read_text()
    values = []
    for name in ("source_path", "source_namespace", "source_function"):
        match = re.search(r"fn " + name + r"\(\).*?\n\}", source, re.S)
        assert match, (path, name)
        chunks = re.findall(r'text\.append\(("(?:[^"\\]|\\.)*")\);', match[0])
        values.append("".join(ast.literal_eval(chunk) for chunk in chunks))
    return "::".join(values)


with tempfile.TemporaryDirectory(prefix="goosetest-limits-") as temporary:
    work = Path(temporary).resolve()
    project = work / "large consumer"
    (project / "src").mkdir(parents=True)
    (project / "test").mkdir()
    (work / "package").symlink_to(repo, target_is_directory=True)
    (project / "goosetest_root.goose").write_text(
        'import goosetest from "../package";\nimport goosetest_generated.runner;\n'
        'fn main() { exit(goosetest_generated::run_all()); }\n')
    expected = []
    expected_listing = []
    for index in range(129):
        name = f"module_{index:03}"
        (project / "src" / f"{name}.goose").write_text(
            f"namespace {name};\nfn value() -> i64 {{ return {index}; }}\n")
        lines = [f"namespace {name}_test;", "import goosetest;", f"import src.{name};"]
        cases = [f"case_{number:03}" for number in range(65)] if index == 0 else ["first", "second"]
        for case in cases:
            function = f"test_{case}"
            identity = f"test/{name}_test.goose::{name}_test::{function}"
            lines.append(f"fn {function}(t: goosetest::Test&) {{ t.assert_eq({index}, {name}::value()); }}")
            expected.append(identity)
            expected_listing.append(f"unit  {identity}  (test/{name}_test.goose:{len(lines)}:1)")
        (project / "test" / f"{name}_test.goose").write_text("\n".join(lines) + "\n")
    assert len(list((project / "src").glob("*.goose"))) == 129
    assert len(list((project / "test").glob("*.goose"))) == 129
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))
    listing = call(["list", "--project", str(project)], work, env)
    assert not listing.stderr, listing.stderr
    assert listing.stdout.decode().splitlines() == expected_listing + [
        "321 discovered cases: 321 executable, 0 disabled"]
    compiler = work / "compiler"
    log = work / "compiler.json"
    real_goose = shutil.which("goose")
    assert real_goose
    compiler.write_text(f"#!{sys.executable}\nimport json, os, sys\n"
                        f"open({str(log)!r}, 'w').write(json.dumps(sys.argv[1:]))\n"
                        f"os.execv({real_goose!r}, [{real_goose!r}, *sys.argv[1:]])\n")
    compiler.chmod(0o700)
    result = call(["test", "--project", str(project), "--compiler", str(compiler)], work, env)
    invocation = json.loads(log.read_text())
    assert invocation == ["build", "goosetest_root.goose", "-O0", "--debug", "-o",
                          "./goosetest_generated/tests"], invocation
    passed = re.findall(r"^PASS (\S+) \(", result.stdout.decode(), re.M)
    assert passed == expected, (len(passed), passed)
    assert "Cases: 321 passed, 0 failed, 0 skipped, 0 errors, 0 not run" in result.stdout.decode()
    generated = project / "goosetest_generated"
    wrappers = sorted(generated.glob("case_*.goose"), key=lambda p: int(p.stem[5:]))
    assert [wrapper_identity(path) for path in wrappers] == expected
    # Exceed the real default file limit; discovery must fail before compilation starts.
    log.unlink()
    oversized = project / "src/module_000.goose"
    oversized.write_bytes(b"/" * (1048576 + 1))
    rejected = call(["test", "--project", str(project), "--compiler", str(compiler)], work, env, 2)
    diagnostic = rejected.stderr.decode()
    assert "src/module_000.goose" in diagnostic, diagnostic
    assert "limit" in diagnostic.lower() and "1048576" in diagnostic, diagnostic
    assert "Discovery incomplete; no tests executed." in diagnostic, diagnostic
    assert not log.exists(), "discovery failure must not invoke the compiler"
    assert not re.search(rb"^PASS ", rejected.stdout, re.M), rejected.stdout
print("limits regression passed: 321 exact IDs; 129 files per root, 65 cases in one module; oversized source rejected")
