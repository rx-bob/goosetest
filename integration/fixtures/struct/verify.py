"""Independent permissions-example status and ordered field-diagnostic oracle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
cli = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="goosetest-struct-") as tmp:
    project = Path(tmp)
    (project / "src").mkdir()
    (project / "test").mkdir()
    (project / "goosetest_root.goose").write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    (project / "src/permissions.goose").write_text('''// Representative comparable permission result.
namespace permissions;

struct Decision {
    allowed: bool,
    effective_role: const u8[:],
    reason: const u8[:],
}

fn viewer() -> Decision {
    return Decision {
        allowed: false,
        effective_role: "viewer",
        reason: "insufficient_role",
    };
}
''')
    env = dict(os.environ, GOOSE_HOME=str(project / "cache"))
    def run(allowed, reason, status):
        (project / "test/permissions_test.goose").write_text('''// Passing and negative variants share authored source and generated execution.
namespace permissions_test;

import goosetest;

import src.permissions;

fn test_viewer(t: goosetest::Test&) {
    let expected = permissions::Decision {
        allowed: ALLOWED,
        effective_role: "viewer",
        reason: "REASON",
    };
    var actual = permissions::viewer();
    t.assert_struct_eq(expected, actual, "viewer write check");
}

fn test_later(t: goosetest::Test&) {
    t.assert_true(true);
}
'''.replace('ALLOWED', allowed).replace('REASON', reason))
        result = subprocess.run([cli, 'test', '--project', str(project)], env=env,
                                capture_output=True, timeout=120)
        assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
        assert b'PASS test/permissions_test.goose::permissions_test::test_later' in result.stdout
        return result.stdout
    out = run('false', 'insufficient_role', 0)
    assert b'2 passed' in out and b'struct fields differ' not in out
    out = run('true', 'ok', 1)
    diagnostic = (b'viewer write check: struct fields differ:\n'
                  b'.allowed expected: <true> actual: <false>\n'
                  b'.reason expected: <ok> actual: <insufficient_role>\n')
    assert diagnostic in out, out
    assert b'.effective_role' not in out
    assert b'1 passed, 1 failed' in out
    for name, diagnostic in (("mismatched_types", b"no matching overload"),
                             ("nonstruct", b"fields requires")):
        source = (Path(__file__).parent / (name + ".goose.data")).read_text()
        path = project / (name + ".goose")
        path.write_text(source.replace("PACKAGE_PATH", str(repo)))
        result = subprocess.run(["goose", "build", "--debug", str(path), "-o", str(project / name)],
                                env=env, capture_output=True, timeout=120)
        assert result.returncode != 0, name
        assert diagnostic in result.stdout + result.stderr, (name, result.stdout, result.stderr)
        assert not (project / name).exists()
print('struct assertion process tests passed')
