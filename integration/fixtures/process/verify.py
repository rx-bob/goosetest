"""External lifecycle oracle; adapter results alone cannot establish child cleanup."""
import errno
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

driver, child, unit = (str(Path(p).resolve()) for p in sys.argv[1:])


def result(output):
    line = output.decode().splitlines()[-1]
    fields = line.split()
    assert fields[0] == "RESULT", output
    return dict(kind=fields[1], code=int(fields[2]), signal=int(fields[3]),
                error=int(fields[4]), pid=int(fields[5]), reaped=fields[6], cleanup=int(fields[7]))


def gone(pid, allow_zombie=False):
    if not pid:
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    if allow_zombie:
        state = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="],
                               capture_output=True, text=True, timeout=2).stdout.strip()
        return not state or state.startswith("Z")
    return False


def check_reaped(record):
    assert record["reaped"] == "true" and record["cleanup"] == 0, record
    assert gone(record["pid"]), record


def invoke(cwd, executable, *args, scenario="normal", environment=None):
    response = subprocess.run([driver, scenario, str(cwd), executable, *args],
                              capture_output=True, timeout=8, env=environment)
    assert response.returncode == 0, response.stderr
    return response, result(response.stdout)


with tempfile.TemporaryDirectory(prefix="goosetest-process-") as temporary:
    root = Path(temporary).resolve()
    cwd = root / 'cwd space "quote" $cash;semi'
    cwd.mkdir()
    executable = cwd / 'child space "quote" $cash;semi'
    shutil.copy2(child, executable)
    subprocess.run([unit, str(executable), str(cwd)], check=True, timeout=10)
    arguments = ["", "space value", 'double"quote', "single'quote", "$HOME", "a;touch injected", "\\slash", "line\nbreak"]
    response, record = invoke(cwd, str(executable), "echo", *arguments)
    expected = "cwd=" + str(cwd) + "\n" + "".join("arg=" + a + "\n" for a in arguments)
    assert response.stdout.startswith(expected.encode()), response.stdout
    assert response.stderr == b"child stderr inherited\n"
    assert record["kind"] == "exit" and record["code"] == 0
    check_reaped(record)
    assert not (cwd / "injected").exists()
    inherited = subprocess.run([driver, "normal", str(cwd), str(executable), "stdin"],
                               input=b"inherited input\n", capture_output=True, timeout=8)
    assert inherited.returncode == 0 and inherited.stdout.startswith(b"stdin=inherited input\n")
    check_reaped(result(inherited.stdout))
    _, relative = invoke(cwd, "./" + executable.name, "exit", "7")
    assert relative["kind"] == "exit" and relative["code"] == 7
    check_reaped(relative)
    environment = dict(os.environ, PATH=str(cwd))
    _, searched = invoke(cwd, executable.name, "exit", "127", environment=environment)
    assert searched["kind"] == "exit" and searched["code"] == 127
    check_reaped(searched)
    _, missing = invoke(cwd, str(cwd / "missing"), "exit", "0")
    assert missing["kind"] == "launch" and missing["error"] == errno.ENOENT
    assert missing["pid"] == 0 and missing["reaped"] == "false"
    script = cwd / "not-an-executable-format"
    script.write_text("touch shell-fallback-ran\n")
    script.chmod(0o755)
    _, no_shell = invoke(cwd, str(script), "unused")
    assert no_shell["kind"] == "launch" and no_shell["error"] == errno.ENOEXEC, no_shell
    assert not (cwd / "shell-fallback-ran").exists()
    _, no_shell_path = invoke(cwd, script.name, "unused", environment=environment)
    assert no_shell_path["kind"] == "launch" and no_shell_path["error"] == errno.ENOEXEC
    assert not (cwd / "shell-fallback-ran").exists()
    started = time.monotonic()
    _, search_timeout = invoke(cwd, "missing-in-every-path-entry", "unused", scenario="deadline",
                               environment=dict(os.environ, PATH=":" * 60000))
    assert search_timeout["kind"] == "deadline" and search_timeout["pid"] == 0, search_timeout
    assert time.monotonic() - started < 2
    _, signaled = invoke(cwd, str(executable), "signal")
    assert signaled["kind"] == "signal" and signaled["signal"] == signal.SIGUSR1
    check_reaped(signaled)
    for scenario, mode, cancellation in [("deadline", "wait", None), ("deadline", "tree", None),
                                         ("normal", "tree", signal.SIGINT),
                                         ("normal", "graceful", signal.SIGTERM), ("normal", "orphan", None)]:
        ready = root / (scenario + mode + str(cancellation))
        process = subprocess.Popen([driver, scenario, str(cwd), str(executable), mode, str(ready)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        started = time.monotonic()
        pids = []
        try:
            until = started + 3
            while time.monotonic() < until:
                if ready.exists() and len(ready.read_text().split()) == 2:
                    pids = [int(value) for value in ready.read_text().split()]
                    break
                assert process.poll() is None, process.communicate()
                time.sleep(0.005)
            assert pids, "child never became ready"
            if cancellation:
                os.kill(process.pid, cancellation)
            stdout, stderr = process.communicate(timeout=3)
            elapsed = time.monotonic() - started
            assert process.returncode == 0 and stderr == b"", (stdout, stderr)
            record = result(stdout)
            expected_kind = "exit" if mode == "orphan" else ("cancel" if cancellation else "deadline")
            assert record["kind"] == expected_kind, record
            if mode == "orphan":
                assert record["code"] == 0, record
            if cancellation:
                assert record["signal"] == cancellation, record
            assert elapsed < 2, ("deadline/grace exceeded generous scheduling allowance", elapsed)
            check_reaped(record)
            until = time.monotonic() + 2
            while not all(gone(pid, allow_zombie=True) for pid in pids) and time.monotonic() < until:
                time.sleep(0.01)
            assert all(gone(pid, allow_zombie=True) for pid in pids), pids
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            for pid in pids:
                if pid and not gone(pid, allow_zombie=True):
                    os.kill(pid, signal.SIGKILL)
print("process lifecycle tests passed")
