"""External status and inventory oracle for the generated repository test runner."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[3]
TOKEN = re.compile(r'[A-Za-z_][A-Za-z_0-9]*|[^\s]')


def source_tokens(source):
    """Skip comments and quoted literals before recognizing declarations."""
    cursor = 0
    while cursor < len(source):
        if source.startswith('//', cursor):
            end = source.find('\n', cursor)
            cursor = len(source) if end < 0 else end
        elif source.startswith('/*', cursor):
            cursor += 2
            depth = 1
            while depth:
                assert cursor < len(source), 'unclosed block comment'
                if source.startswith('/*', cursor):
                    depth += 1
                    cursor += 2
                elif source.startswith('*/', cursor):
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
        elif source[cursor] in '\"\'':
            delimiter = '"""' if source.startswith('"""', cursor) else source[cursor]
            cursor += len(delimiter)
            while not source.startswith(delimiter, cursor):
                assert cursor < len(source), 'unclosed quoted literal'
                cursor += 2 if source[cursor] == '\\' else 1
            cursor += len(delimiter)
        elif source[cursor].isspace():
            cursor += 1
        else:
            match = TOKEN.match(source, cursor)
            yield match.group(), match.start()
            cursor = match.end()


def inventory(project):
    records = {}
    for directory in ('test', 'integration'):
        for path in sorted((project / directory).rglob('*.goose')):
            assert path.name.endswith('_test.goose'), path
            tokens = list(source_tokens(path.read_text()))
            namespace = None
            depth = 0
            count = 0
            for index, (token, offset) in enumerate(tokens):
                if depth == 0 and token == 'namespace':
                    namespace = tokens[index + 1][0]
                if depth == 0 and token == 'fn' and tokens[index + 1][0].startswith('test_'):
                    assert namespace, path
                    name = tokens[index + 1][0]
                    identity = f'{path.relative_to(project).as_posix()}::{namespace}::{name}'
                    assert identity not in records, identity
                    records[identity] = (path.relative_to(project), offset)
                    count += 1
                if token == '{':
                    depth += 1
                elif token == '}':
                    depth -= 1
                    assert depth >= 0, path
            assert depth == 0 and count > 0, path
    assert records, 'empty source inventory'
    return records


def run(argv, env, status=0, cwd=REPO):
    result = subprocess.run([str(value) for value in argv], cwd=cwd, env=env,
                            capture_output=True, text=True, timeout=900)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result.stdout


def listed(output):
    return [line.split()[1] for line in output.splitlines()
            if line.startswith(('unit  ', 'integration  '))]


def rows(output, outcome):
    return re.findall(r'^' + re.escape(outcome) + r' ([^ ]+) ', output, re.MULTILINE)


def main():
    expected = inventory(REPO)
    with tempfile.TemporaryDirectory(prefix='goosetest-self-host-') as temporary:
        work = Path(temporary)
        scratch = work / 'scratch'
        scratch.mkdir()
        env = dict(os.environ, GOOSE_HOME=str(work / 'cache'), TMPDIR=str(scratch))
        cli = work / 'goosetest'
        run(['goose', 'build', '--debug', REPO / 'main.goose', '-o', cli], env)
        run([cli, 'check-mirror', '--project', REPO], env)
        actual = listed(run([cli, 'list', '--project', REPO], env))
        assert sorted(actual) == sorted(expected), (actual, sorted(expected))
        output = run([cli, 'test', '--project', REPO, '--compile-timeout-seconds', '600',
                      '--run-timeout-seconds', '600'], env)
        assert sorted(rows(output, 'PASS')) == sorted(expected), output
        assert not any(rows(output, state) for state in ('FAIL', 'SKIP', 'NOT RUN', 'ERROR')), output

        clone = work / 'injected'
        shutil.copytree(REPO, clone, ignore=shutil.ignore_patterns(
            '.git', 'goosetest_generated', 'cache', '__pycache__', '.DS_Store'))
        identity = 'integration/self_host_test.goose::self_host_integration_test::test_generated_identity'
        relative, offset = expected[identity]
        target = clone / relative
        source = target.read_text()
        opening = source.index('{', offset)
        source = source[:opening + 1] + '\n    outer.fail("external failure injection");' + source[opening + 1:]
        target.write_text(source)
        failed = run([cli, 'test', '--project', clone, '--compile-timeout-seconds', '600',
                      '--run-timeout-seconds', '600'], env, status=1)
        assert rows(failed, 'FAIL') == [identity], failed
        assert 'external failure injection' in failed, failed
        assert sorted(rows(failed, 'PASS')) == sorted(set(expected) - {identity}), failed
        print(f'self-host verified: {len(expected)} discovered and passing; injected assertion exits 1')


if __name__ == '__main__':
    main()
