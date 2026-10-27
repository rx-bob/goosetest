"""Exercise new assertions through generated consumer calls and shell statuses."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
cli = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="goosetest-values-") as tmp:
    project = Path(tmp)
    (project / "src").mkdir()
    (project / "test").mkdir()
    (project / "src/value.goose").write_text("namespace value;\n")
    (project / "goosetest_root.goose").write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    env = dict(os.environ, GOOSE_HOME=str(project / "cache"))
    def run(body, status, expected):
        (project / "test/value_test.goose").write_text(
            'namespace value_test;\nimport goosetest;\nimport std;\n'
            f'fn test_values(t: goosetest::Test&) {{ {body} }}\n'
            'fn test_later(t: goosetest::Test&) { print("LATER"); }\n')
        result = subprocess.run([cli, "test", "--project", str(project)],
                                env=env, capture_output=True, timeout=120)
        assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
        assert expected in result.stdout, result.stdout
        return result.stdout
    run('t.assert_contains("oo", "goose"); t.assert_near(1.0, 1.25, 0.25);', 0, b"2 passed")
    out = run('t.assert_contains("duck", "goose", "species"); print("UNREACHABLE");', 1,
              b"species: expected fragment: <duck> actual: <goose>")
    assert b"LATER" in out and b"UNREACHABLE" not in out
    run('t.assert_near(1.0, 1.25, 0.1, "distance");', 1, b"absolute tolerance:")
    run('t.assert_near(1.0, 1.0, -1.0);', 1, b"tolerance must be finite and nonnegative")
print("value assertion process tests passed")
