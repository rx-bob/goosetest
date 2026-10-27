"""Run independent failure/completeness oracles with parent-owned resource cleanup."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
MAX_LOG_BYTES = 8 * 1024 * 1024
STAGE_SECONDS = 900


def group_alive(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def clean_group(group):
    """Own the oracle group; stage fixtures separately track their detached child groups."""
    deadline = time.monotonic() + 10
    while group_alive(group):
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f'could not clean owned process group {group}')
        time.sleep(.05)


def run_owned(label, argv, env, work):
    """Bound output/time, check status, and reject children left after the oracle exits."""
    with tempfile.TemporaryFile(dir=work) as output:
        proc = subprocess.Popen([str(value) for value in argv], cwd=REPO, env=env,
                                stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        problem = None
        try:
            deadline = time.monotonic() + STAGE_SECONDS
            while proc.poll() is None:
                if time.monotonic() >= deadline:
                    problem = 'parent deadline exceeded'
                    break
                if os.fstat(output.fileno()).st_size > MAX_LOG_BYTES:
                    problem = 'parent output budget exceeded'
                    break
                time.sleep(.05)
            if problem:
                proc.kill()
            proc.wait(timeout=10)
            size = os.fstat(output.fileno()).st_size
            if size > MAX_LOG_BYTES:
                problem = 'parent output budget exceeded'
            output.seek(0)
            text = output.read(MAX_LOG_BYTES).decode(errors='replace')
            if problem or proc.returncode != 0:
                raise RuntimeError(f'{label}: {problem or "exit " + str(proc.returncode)}\n{text}')
            if group_alive(proc.pid):
                raise RuntimeError(f'{label}: owned process group survived: {proc.pid}\n{text}')
            print(f'PASS oracle: {label}', flush=True)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=10)
            clean_group(proc.pid)


def main():
    with tempfile.TemporaryDirectory(prefix='goosetest-verification-') as temporary:
        work = Path(temporary)
        scratch = work / 'scratch'
        scratch.mkdir()
        env = dict(os.environ, GOOSE_HOME=str(work / 'cache'), TMPDIR=str(scratch),
                   PYTHONOPTIMIZE='0', PYTHONDONTWRITEBYTECODE='1')
        cli = work / 'goosetest'
        oracle = work / 'cli-oracle'
        for source, binary in [('main.goose', cli), ('test_support/oracles/cli_test.goose', oracle)]:
            run_owned('build ' + source, ['goose', 'build', '--debug', REPO / source, '-o', binary], env, work)
        matrices = [
            ('self_host', [cli]), ('cli', [cli, oracle]), ('execution', [cli]),
            ('artifacts', [cli]), ('limits', [cli]), ('disabled', [cli]),
            ('selection', [cli]), ('lifecycle', [cli]), ('suite', [cli]),
            ('pretty_goose', [cli]),
        ]
        for name, arguments in matrices:
            path = REPO / 'integration' / 'fixtures' / name / 'verify.py'
            run_owned(name, [sys.executable, '-B', path, *arguments], env, work)
    print('independent self-host and failure-contract verification passed')


if __name__ == '__main__':
    main()
