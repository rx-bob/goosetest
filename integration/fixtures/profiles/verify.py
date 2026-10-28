"""Independent compiler argv and real-profile consumer oracle."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]
real_goose = shutil.which("goose")
assert real_goose


def run(args, cwd, env, status=0):
    result = subprocess.run([cli, *args], cwd=cwd, env=env, capture_output=True, timeout=240)
    assert result.returncode == status, (args, result.returncode, result.stdout, result.stderr)
    return result


with tempfile.TemporaryDirectory(prefix="goosetest-profile-") as temporary:
    work = Path(temporary).resolve()
    project = work / "consumer space ;$(literal)"
    (project / "src").mkdir(parents=True)
    (project / "test").mkdir()
    (work / "package").symlink_to(repo, target_is_directory=True)
    (project / "goosetest_root.goose").write_text(
        'import goosetest from "../package";\nimport goosetest_generated.runner;\n'
        'fn main() { exit(goosetest_generated::run_all()); }\n')
    (project / "src/value.goose").write_text(
        'namespace value;\nfn answer() -> i64 { return 42; }\n')
    (project / "test/value_test.goose").write_text(
        'namespace value_test;\nimport goosetest;\nimport src.value;\n'
        'fn test_answer(t: goosetest::Test&) { t.assert_eq(42, value::answer()); }\n')

    log = work / "argv.json"
    compiler = project / "compiler path ;$(literal)"
    compiler.write_text(
        f"#!{sys.executable}\nimport json, os, sys\n"
        f"open({str(log)!r}, 'w').write(json.dumps(sys.argv[1:]))\n"
        f"os.execv({real_goose!r}, [{real_goose!r}, *sys.argv[1:]])\n")
    compiler.chmod(0o700)
    env = dict(os.environ, GOOSE_HOME=str(work / "goose cache"))
    entry = "goosetest_root.goose"
    output = "./goosetest_generated/tests"

    run(["test", "--project", str(project), "--compiler", str(compiler)], work, env)
    assert json.loads(log.read_text()) == ["build", entry, "-O0", "--debug", "-o", output]

    run(["test", "--project", str(project), "--profile", "debug", "--offline",
         "--compiler", str(compiler)], work, env)
    assert json.loads(log.read_text()) == ["build", entry, "-O0", "--debug", "--offline", "-o", output]

    run(["test", "--project", str(project), "--profile", "optimized", "--compiler", str(compiler)], work, env)
    optimized = json.loads(log.read_text())
    assert optimized == ["build", entry, "-O2", "-o", output], optimized
    assert "--debug" not in optimized and "-O0" not in optimized

    log.unlink()
    for args in [
        ["test", "--project", str(project), "--profile", "both", "--compiler", str(compiler)],
        ["list", "--project", str(project), "--profile", "optimized"],
        ["test", "--project", str(project), "--offline", "--offline"],
    ]:
        rejected = run(args, work, env, 2)
        assert b"Usage:" in rejected.stderr
        assert not log.exists(), (args, "compiler was invoked")

print("profile compiler argv and consumer tests passed")
