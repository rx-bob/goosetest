"""Independent suite-hook order, status, isolation and case-accounting oracle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
cli = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="goosetest-suite-") as tmp:
    project = Path(tmp)
    (project / "src").mkdir()
    (project / "test").mkdir()
    for name in ('a', 'b', 'c'):
        (project / f"src/{name}.goose").write_text(f"namespace {name};\n")
    (project / "goosetest_root.goose").write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    env = dict(os.environ, GOOSE_HOME=str(project / "cache"))
    template = '''// Suite hooks surround every selected case, without sharing a fixture.
namespace a_test;
import goosetest;
import std;
fn initialize() -> i64 { print("EVENT A CONSTRUCT"); return 7; }
struct Fixture { value: i64 = initialize() }
fn before_all(t: goosetest::Test&) {
    print("EVENT A SETUP");
    SETUP
}
fn after_all(t: goosetest::Test&) {
    print("EVENT A CLEANUP");
    CLEANUP
}
fn before_each(f: Fixture&) { print("EVENT A EACH SETUP"); }
fn after_each(f: Fixture&) { print("EVENT A EACH CLEANUP"); }
fn test_one(t: goosetest::Test&, f: Fixture&) {
    print("EVENT A ONE");
    t.assert_eq(7, f.value);
    BODY
}
fn test_two(t: goosetest::Test&) { print("EVENT A TWO"); t.assert_true(true); }
'''
    (project / 'test/b_test.goose').write_text('''namespace b_test;
import goosetest;
import std;
fn test_b(t: goosetest::Test&) { print("EVENT B BODY"); t.assert_true(true); }
''')
    (project / 'test/c_test.goose').write_text('''namespace c_test;
import goosetest;
import std;
fn before_all() { print("EVENT C SETUP"); }
fn after_all() { print("EVENT C CLEANUP"); }
fn test_c(t: goosetest::Test&) { print("EVENT C BODY"); t.assert_true(true); }
''')
    scenarios = {
        'pass': ('t.assert_true(true);', 't.assert_true(true);', '', 0, 4, 0, 0, 0),
        'setup': ('t.fail("suite setup cause"); print("NEVER");', '', '', 1, 2, 0, 2, 1),
        'soft_setup': ('t.check_eq(1, 2, "suite setup cause");', '', '', 1, 2, 0, 2, 1),
        'cleanup': ('', 't.fail("suite cleanup cause");', '', 1, 4, 0, 0, 1),
        'both': ('t.fail("suite setup cause");', 't.fail("suite cleanup cause");', '', 1, 2, 0, 2, 2),
        'body_cleanup': ('', 't.fail("suite cleanup cause");', 't.fail("body cause");', 1, 3, 1, 0, 1),
        'two_checks': ('t.check_eq(1, 2, "first"); t.check_eq(3, 4, "second");', '', '', 1, 2, 0, 2, 1),
    }
    for mode, (setup, cleanup, body, status, passed, failed, skipped, hook_errors) in scenarios.items():
        source = template.replace('    SETUP\n', '    '+setup+'\n').replace('    CLEANUP\n', '    '+cleanup+'\n')
        source = source.replace('    BODY\n', '    '+body+'\n')
        (project / 'test/a_test.goose').write_text(source)
        result = subprocess.run([cli, 'test', '--project', str(project)], env=env,
                                capture_output=True, timeout=120)
        assert result.returncode == status, (mode, result.returncode, result.stdout, result.stderr)
        output = result.stdout
        events = [line.decode() for line in output.splitlines() if line.startswith(b'EVENT ')]
        expected = ['EVENT A SETUP']
        if not skipped:
            expected += ['EVENT A CONSTRUCT', 'EVENT A EACH SETUP', 'EVENT A ONE', 'EVENT A EACH CLEANUP', 'EVENT A TWO']
        expected += ['EVENT A CLEANUP', 'EVENT B BODY', 'EVENT C SETUP', 'EVENT C BODY', 'EVENT C CLEANUP']
        assert events == expected, (mode, events, output)
        summary = f'Cases: {passed} passed, {failed} failed, {skipped} skipped, 0 errors, 0 not run'.encode()
        assert summary in output, (mode, output)
        assert f'suite-hook errors: {hook_errors}'.encode() in output, (mode, output)
        assert b'NEVER' not in output
        if skipped:
            assert b'suite setup failed' in output and b'[suite setup]' in output
        if 'cleanup cause' in cleanup:
            assert b'[suite cleanup]' in output and b'suite cleanup cause' in output
        if mode == 'both':
            assert output.index(b'[suite setup]') < output.index(b'[suite cleanup]')
        if mode == 'two_checks':
            assert b'first:' in output and b'second:' in output
        # Suite-hook diagnostics must never fabricate a case outcome.
        case_rows = [line for line in output.splitlines() if line.startswith((b'PASS ', b'FAIL ', b'SKIP ', b'ERROR '))]
        assert len(case_rows) == 4, (mode, case_rows)
        generated = project / 'goosetest_generated'
        subprocess.run(['goosefmt', 'check', '--config', str(repo / '.goosefmt.toml'), str(generated)],
                       check=True, capture_output=True, timeout=15)
        for path in generated.glob('*.goose'):
            lines = path.read_text().splitlines()
            assert len(lines) <= 500
            starts = [i for i, line in enumerate(lines) if line.startswith('fn ')] + [len(lines)]
            for a, b in zip(starts, starts[1:]):
                assert len('\n'.join(lines[a:b]).rstrip().splitlines()) <= 70, path
    # Incomplete setup still reaches the last wrapper across a dispatch boundary.
    tests = "\n".join(f'fn test_{index}(t: goosetest::Test&) {{ print("NEVER BODY"); }}'
                      for index in range(40))
    (project / 'test/a_test.goose').write_text('namespace a_test;\nimport goosetest;\nimport std;\nfn before_all(t: goosetest::Test&) {\n    print("EVENT A SETUP");\n    var message: u8[>..] = [];\n    for index in 0..1048577 { message.push(\'x\'); }\n    t.fail(message);\n}\nfn after_all() { print("EVENT A CLEANUP"); }\n' + tests)
    result = subprocess.run([cli, 'test', '--project', str(project)], env=env,
                            capture_output=True, timeout=120)
    assert result.returncode == 2, (result.returncode, result.stdout, result.stderr)
    assert [line for line in result.stdout.splitlines() if line.startswith(b'EVENT ')] == [
        b'EVENT A SETUP', b'EVENT A CLEANUP']
    assert b'42 not run' in result.stdout and b'diagnostic byte limit exhausted' in result.stdout
    assert b'NEVER BODY' not in result.stdout
print('suite hook process tests passed')
