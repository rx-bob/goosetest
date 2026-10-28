"""Independent selection, cold call-graph and fail-fast cleanup oracle."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix="goosetest-selection-") as tmp:
    project = Path(tmp)
    for name in ('src', 'test', 'integration'):
        (project / name).mkdir()
    for name in ('a', 'b'):
        (project / f'src/{name}.goose').write_text(f'namespace {name};\n')
    (project / 'goosetest_root.goose').write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    env = dict(os.environ, GOOSE_HOME=str(project / 'cache'))
    a = '''// Selected cases keep per-case and suite cleanup boundaries.
namespace a_test;
import goosetest;
import std;
fn initialize() -> i64 { print("EVENT A CONSTRUCT"); return 7; }
struct Fixture { value: i64 = initialize() }
fn before_all(t: goosetest::Test&) { print("EVENT A SETUP"); SETUP }
fn after_all(t: goosetest::Test&) { print("EVENT A CLEANUP"); CLEANUP }
fn before_each(t: goosetest::Test&, f: Fixture&) { print("EVENT A EACH SETUP"); }
fn after_each(t: goosetest::Test&, f: Fixture&) { print("EVENT A EACH CLEANUP"); }
// @DisplayName("pretty label")
fn test_first(t: goosetest::Test&, f: Fixture&) { print("EVENT A FIRST"); t.assert_eq(7, f.value); BODY }
fn test_second(t: goosetest::Test&) { print("EVENT A SECOND"); t.assert_true(true); }
// @Disabled("own reason")
fn test_disabled(t: goosetest::Test&, f: Fixture&) { print("NEVER DISABLED"); t.fail("disabled"); }
'''
    b = '''namespace b_test;
import goosetest;
import std;
fn before_all() { print("EVENT B SETUP"); }
fn after_all() { print("EVENT B CLEANUP"); }
fn test_later(t: goosetest::Test&) { print("EVENT B BODY"); t.assert_true(true); }
'''
    integration = '''namespace flow_test;
import goosetest;
import std;
fn test_flow(t: goosetest::Test&) { print("EVENT INTEGRATION"); t.assert_true(true); }
'''
    def write(setup='', cleanup='', body=''):
        source = a.replace(' SETUP }', ' '+setup+' }').replace(' CLEANUP }', ' '+cleanup+' }')
        source = source.replace(' BODY }', ' '+body+' }')
        (project / 'test/a_test.goose').write_text(source)
        (project / 'test/b_test.goose').write_text(b)
        (project / 'integration/flow_test.goose').write_text(integration)

    def run(command='test', extra=(), status=0, contains=b''):
        result = subprocess.run([cli, command, '--project', str(project), *extra], env=env,
                                capture_output=True, timeout=120)
        assert result.returncode == status, (command, extra, result.returncode, result.stdout, result.stderr)
        assert contains in result.stdout + result.stderr, (contains, result.stdout, result.stderr)
        return result

    def events(result):
        return [line.decode() for line in result.stdout.splitlines() if line.startswith(b'EVENT ')]

    def listed(result):
        return [line.split()[1].decode() for line in result.stdout.splitlines()
                if line.startswith((b'unit  ', b'integration  '))]

    def reported(result):
        return [match.group(1).decode() for line in result.stdout.splitlines()
                if (match := re.match(rb'^(?:PASS|FAIL|SKIP|NOT RUN|ERROR) ([^ ]+) ', line))]

    write()
    for options in ((), ('--suite', 'unit'), ('--suite', 'integration'), ('--suite', 'all'),
                    ('--filter', '::test_first'), ('--filter', '.goose::'), ('--filter', ''),
                    ('--suite', 'unit', '--filter', '::test_disabled')):
        ids = listed(run('list', options))
        executed = run(extra=options)
        assert reported(executed) == ids, (options, ids, reported(executed))
    disabled = run(extra=('--filter', '::test_disabled'))
    assert events(disabled) == [] and b'0 passed, 0 failed, 1 skipped' in disabled.stdout
    assert b'0 not run; 4 filtered' in disabled.stdout
    assert b'own reason' in disabled.stdout and b'Assertions: 0;' in disabled.stdout

    for literal in ('test_.*', '*', '[first]', 'pretty label', 'no match'):
        for command in ('list', 'test'):
            result = run(command, ('--filter', literal), 2, b'zero cases')
            assert events(result) == []
    run('list', ('--suite', 'integration', '--filter', '::test_first'), 2, b'zero cases')
    integration_path = project / 'integration/flow_test.goose'
    integration_path.unlink()
    for command in ('list', 'test'):
        run(command, ('--suite', 'integration'), 2, b'zero cases')
    integration_path.write_text(integration)
    before = listed(run('list', ('--filter', '::test_first')))
    path = project / 'test/a_test.goose'
    path.write_text(path.read_text().replace('pretty label', 'changed display label'))
    assert listed(run('list', ('--filter', '::test_first'))) == before
    assert reported(run(extra=('--filter', '::test_first'))) == before
    run('list', ('--filter', 'changed display label'), 2, b'zero cases')

    write()
    selected_b = run(extra=('--filter', '::test_later'))
    assert events(selected_b) == ['EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP']
    assert b'4 filtered' in selected_b.stdout
    # Hard assertion returns in cold bodies retain their required runtime ancestry.
    write(body='t.assert_true(false); t.fail("filtered hard return"); print("NEVER FILTERED");')
    cold = run(extra=('--filter', '::test_later'))
    assert events(cold) == ['EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP']
    assert b'NEVER FILTERED' not in cold.stdout and b'4 filtered' in cold.stdout
    # Unselected sources, constructors and hooks still compile in their recovery ancestry.
    invalid_changes = [
        ('test/b_test.goose', 't.assert_true(true);', 'unknown_filtered_body();'),
        ('test/a_test.goose', 'return 7;', 'return "wrong fixture value";'),
        ('test/a_test.goose', 'print("EVENT A EACH SETUP");', 'unknown_filtered_each();'),
        ('test/a_test.goose', 'print("EVENT A SETUP");', 'unknown_filtered_suite();'),
        ('test/a_test.goose', 'print("EVENT A EACH CLEANUP");', 'unknown_filtered_each_cleanup();'),
        ('test/a_test.goose', 'print("EVENT A CLEANUP");', 'unknown_filtered_suite_cleanup();'),
    ]
    for filename, old, new in invalid_changes:
        write()
        path = project / filename
        path.write_text(path.read_text().replace(old, new))
        selected = '::test_first' if filename.startswith('test/b') else '::test_later'
        result = run(extra=('--filter', selected), status=2, contains=b'compilation')
        assert events(result) == []
        if new.startswith('unknown_'):
            assert new.split('(')[0].encode() in result.stderr, result.stderr
        assert not (project / 'goosetest_generated/tests').exists()
    write()
    path = project / 'test/b_test.goose'
    path.write_text(b.replace('t: goosetest::Test&', 't: i64'))
    result = run(extra=('--filter', '::test_first'), status=2, contains=b'no tests executed')
    assert events(result) == []
    write()
    missing = project / 'src/missing.goose'
    missing.write_text('namespace missing;\n')
    result = run(extra=('--filter', '::test_first'), status=2, contains=b'no tests executed')
    assert events(result) == []
    missing.unlink()

    active_a = ['EVENT A SETUP', 'EVENT A CONSTRUCT', 'EVENT A EACH SETUP',
                'EVENT A FIRST', 'EVENT A EACH CLEANUP']
    write(body='t.fail("first failed"); print("NEVER BODY");')
    result = run(extra=('--suite', 'unit', '--fail-fast'), status=1)
    assert events(result) == active_a + ['EVENT A CLEANUP'], result.stdout
    assert b'Cases: 0 passed, 1 failed, 1 skipped, 0 errors, 2 not run; 1 filtered' in result.stdout
    assert b'NOT RUN test/a_test.goose::a_test::test_second' in result.stdout
    assert b'NOT RUN test/b_test.goose::b_test::test_later' in result.stdout
    assert b'fail-fast' in result.stdout and b'own reason' in result.stdout
    assert b'NEVER BODY' not in result.stdout
    result = run(extra=('--suite', 'unit'), status=1)
    assert events(result) == active_a + ['EVENT A SECOND', 'EVENT A CLEANUP',
                                       'EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP']
    assert b'Cases: 2 passed, 1 failed, 1 skipped, 0 errors, 0 not run; 1 filtered' in result.stdout

    write()
    path = project / 'test/a_test.goose'
    path.write_text(path.read_text().replace('print("EVENT A EACH CLEANUP");',
                                           'print("EVENT A EACH CLEANUP"); t.fail("each cleanup failed");'))
    result = run(extra=('--suite', 'unit', '--fail-fast'), status=1)
    assert events(result) == active_a + ['EVENT A CLEANUP']
    assert b'Cases: 0 passed, 1 failed, 1 skipped, 0 errors, 2 not run; 1 filtered' in result.stdout
    assert b'[cleanup]' in result.stdout and b'each cleanup failed' in result.stdout

    write(setup='t.fail("setup failed");')
    result = run(extra=('--suite', 'unit', '--fail-fast'), status=1)
    assert events(result) == ['EVENT A SETUP', 'EVENT A CLEANUP']
    assert b'Cases: 0 passed, 0 failed, 3 skipped, 0 errors, 1 not run; 1 filtered' in result.stdout
    assert b'suite setup failed' in result.stdout and b'own reason' in result.stdout
    write(cleanup='t.fail("cleanup failed");')
    result = run(extra=('--suite', 'unit', '--fail-fast'), status=1)
    assert events(result) == active_a + ['EVENT A SECOND', 'EVENT A CLEANUP']
    assert b'Cases: 2 passed, 0 failed, 1 skipped, 0 errors, 1 not run; 1 filtered' in result.stdout
    assert b'[suite cleanup]' in result.stdout

    generated = project / 'goosetest_generated'
    formatted = subprocess.run(['goosefmt', 'check', '--config', str(repo / '.goosefmt.toml'), str(generated)],
                               capture_output=True, timeout=15)
    assert formatted.returncode == 0, (formatted.stdout, formatted.stderr)
    for path in generated.glob('*.goose'):
        lines = path.read_text().splitlines()
        assert len(lines) <= 500, path
        starts = [i for i, line in enumerate(lines) if line.startswith('fn ')] + [len(lines)]
        for start, end in zip(starts, starts[1:]):
            assert len('\n'.join(lines[start:end]).rstrip().splitlines()) <= 70, (path, start)
print('selection and fail-fast process tests passed')
