"""Independent disabled-code reachability, typechecking, and metadata oracle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
cli = str(Path(sys.argv[1]).resolve())


def quoted(value):
    result = '"'
    for byte in value:
        if byte == 34:
            result += '\\"'
        elif byte == 92:
            result += '\\\\'
        elif 32 <= byte <= 126:
            result += chr(byte)
        else:
            result += f'\\x{byte:02X}'
    return result + '"'


def escaped(value):
    return b''.join(b'\\\\' if byte == 92 else bytes([byte]) if 32 <= byte <= 126
                    else f'\\x{byte:02X}'.encode() for byte in value)


with tempfile.TemporaryDirectory(prefix="goosetest-disabled-") as temporary:
    project = Path(temporary)
    (project / 'src').mkdir()
    (project / 'test').mkdir()
    (project / 'src/disabled.goose').write_text('namespace disabled;\n')
    (project / 'goosetest_root.goose').write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    test = project / 'test/disabled_test.goose'
    env = dict(os.environ, GOOSE_HOME=str(project / 'cache'))
    label = 'same "label"\\\n\0\x1bé'.encode()
    reason = b'pending "); print("INJECTED"); //\n\0\x1B\\'
    template = '''// Disabled wrappers must remain typechecked without lifecycle side effects.
namespace disabled_test;
import goosetest;
import std;
fn initialize() -> i64 { print("EVENT CONSTRUCT"); return 7; }
struct Fixture { value: i64 = initialize() }
fn before_all(t: goosetest::Test&) { print("EVENT BEFORE_ALL"); t.assert_true(true); }
fn after_all(t: goosetest::Test&) { print("EVENT AFTER_ALL"); t.assert_true(true); }
fn before_each(t: goosetest::Test&, f: Fixture&) { print("EVENT BEFORE_EACH"); t.assert_eq(7, f.value); }
fn after_each(t: goosetest::Test&, f: Fixture&) { print("EVENT AFTER_EACH"); t.assert_eq(7, f.value); }
// @DisplayName(LABEL)
// @Disabled(REASON)
fn test_disabled_plain(t: goosetest::Test&) { print("EVENT DISABLED PLAIN"); t.assert_true(true); t.fail("disabled fail"); }
// @DisplayName(LABEL)
// @Disabled(REASON)
fn test_disabled_fixture(t: goosetest::Test&, f: Fixture&) { print("EVENT DISABLED FIXTURE"); t.assert_eq(8, f.value); }
'''.replace('LABEL', quoted(label)).replace('REASON', quoted(reason))

    def run(source, status):
        test.write_text(source)
        result = subprocess.run([cli, 'test', '--project', str(project)], env=env,
                                capture_output=True, timeout=120)
        assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
        return result.stdout, result.stderr

    def events(output):
        return [line for line in output.splitlines() if line.startswith(b'EVENT ')]

    def style():
        generated = project / 'goosetest_generated'
        subprocess.run(['goosefmt', 'check', '--config', str(repo / '.goosefmt.toml'), str(generated)],
                       check=True, capture_output=True, timeout=15)
        for path in generated.glob('*.goose'):
            lines = path.read_text().splitlines()
            assert len(lines) <= 500, path
            starts = [i for i, line in enumerate(lines) if line.startswith('fn ')] + [len(lines)]
            for start, end in zip(starts, starts[1:]):
                assert len('\n'.join(lines[start:end]).rstrip().splitlines()) <= 70, (path, start)

    out, _ = run(template, 0)
    assert events(out) == [], out
    assert b'Cases: 0 passed, 0 failed, 2 skipped, 0 errors, 0 not run' in out
    assert b'Assertions: 0; suite-hook errors: 0' in out
    assert out.count(b'  display: ' + escaped(label) + b'\n') == 2, out
    assert out.count(b'  reason: ' + escaped(reason) + b'\n') == 2, out
    assert b'SKIP test/disabled_test.goose::disabled_test::test_disabled_plain' in out
    assert b'SKIP test/disabled_test.goose::disabled_test::test_disabled_fixture' in out
    assert b'\nINJECTED\n' not in out
    style()

    # Exact reason budget survives worst-case escaping; one extra byte fails explicitly.
    maximum_reason = b'\x01' * 1024
    maximum = template.replace(quoted(reason), quoted(maximum_reason))
    out, _ = run(maximum, 0)
    assert out.count(b'  reason: ' + escaped(maximum_reason) + b'\n') == 2
    assert events(out) == []
    style()
    out, err = run(template.replace(quoted(reason), quoted(maximum_reason + b'x')), 2)
    assert events(out) == [] and b'disabled reason exceeds' in err, (out, err)

    # Even assertion failures in every hook remain unreachable in an all-disabled suite.
    no_hooks = template.replace('t.assert_true(true); }', 't.fail("disabled hook"); }')
    no_hooks = no_hooks.replace('t.assert_eq(7, f.value); }', 't.fail("disabled each hook"); }')
    out, _ = run(no_hooks, 0)
    assert events(out) == [] and b'2 skipped' in out, out

    enabled = '''
// @DisplayName(LABEL)
fn test_enabled(t: goosetest::Test&, f: Fixture&) { print("EVENT ENABLED"); t.assert_eq(7, f.value); }
'''.replace('LABEL', quoted(label))
    out, _ = run(template + enabled, 0)
    assert events(out) == [b'EVENT BEFORE_ALL', b'EVENT CONSTRUCT', b'EVENT BEFORE_EACH',
                           b'EVENT ENABLED', b'EVENT AFTER_EACH', b'EVENT AFTER_ALL'], out
    assert b'Cases: 1 passed, 0 failed, 2 skipped' in out
    assert out.count(b'  display: ' + escaped(label) + b'\n') == 3
    style()

    # Suite-setup failure must not overwrite explicit disabled reasons.
    failed_setup = (template + enabled).replace('print("EVENT BEFORE_ALL"); t.assert_true(true);',
                                                'print("EVENT BEFORE_ALL"); t.fail("setup cause");')
    out, _ = run(failed_setup, 1)
    assert events(out) == [b'EVENT BEFORE_ALL', b'EVENT AFTER_ALL'], out
    assert b'Cases: 0 passed, 0 failed, 3 skipped' in out
    assert out.count(b'  reason: ' + escaped(reason) + b'\n') == 2, out
    assert out.count(b'  reason: suite setup failed\n') == 1, out
    assert b'suite-hook errors: 1' in out

    # Each disabled dependency must still reach the type checker, despite no runtime execution.
    invalid = {
        'body': template.replace('t.fail("disabled fail");', 'unknown_disabled_body();'),
        'fixture': template.replace('return 7;', 'return "wrong type";'),
        'before_each': template.replace('print("EVENT BEFORE_EACH");', 'unknown_before_each();'),
        'after_each': template.replace('print("EVENT AFTER_EACH");', 'unknown_after_each();'),
        'before_all': template.replace('print("EVENT BEFORE_ALL");', 'unknown_before_all();'),
        'after_all': template.replace('print("EVENT AFTER_ALL");', 'unknown_after_all();'),
    }
    for name, source in invalid.items():
        out, err = run(source, 2)
        assert b'compilation' in err, (name, out, err)
        assert events(out) == [], (name, out)
        assert not (project / 'goosetest_generated/tests').exists(), name

    for annotation in ('@Disabled("")', '@Tag("tag")', '@RepeatedTest(2)', '@Future("unsupported")'):
        source = 'namespace disabled_test;\nimport goosetest;\n// ' + annotation
        source += '\nfn test_invalid(t: goosetest::Test&) { print("EVENT INVALID"); }\n'
        out, err = run(source, 2)
        assert events(out) == [], out
        assert b'no tests executed' in err and b'compilation' not in err, (annotation, err)
print('disabled execution process tests passed')
