"""Independent process oracle for generated per-case fixture lifecycles."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).parent
cli = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="goosetest-lifecycle-") as tmp:
    project = Path(tmp)
    (project / "src").mkdir()
    (project / "test").mkdir()
    (project / "src/lifecycle.goose").write_text("namespace lifecycle;\n")
    (project / "goosetest_root.goose").write_text(
        f'import goosetest from "{repo}";\nimport goosetest_generated.runner;\n'
        'import os;\nfn main() { exit(goosetest_generated::run_all()); }\n')
    test = project / "test/lifecycle_test.goose"
    env = dict(os.environ, GOOSE_HOME=str(project / "cache"))

    def run(source, status):
        test.write_text(source)
        subprocess.run(["goosefmt", "fmt", "--config", str(repo / ".goosefmt.toml"), str(test)],
                       check=True, capture_output=True, timeout=15)
        subprocess.run(["goosefmt", "check", "--config", str(repo / ".goosefmt.toml"), str(test)],
                       check=True, capture_output=True, timeout=15)
        result = subprocess.run([cli, "test", "--project", str(project)], env=env,
                                capture_output=True, timeout=120)
        assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
        generated = project / "goosetest_generated"
        if generated.exists():
            subprocess.run(["goosefmt", "check", "--config", str(repo / ".goosefmt.toml"), str(generated)],
                           check=True, capture_output=True, timeout=15)
            for path in generated.glob("*.goose"):
                lines = path.read_text().splitlines()
                assert len(lines) <= 500, path
                starts = [i for i, line in enumerate(lines) if line.startswith("fn ")] + [len(lines)]
                for start, end in zip(starts, starts[1:]):
                    assert len("\n".join(lines[start:end]).rstrip().splitlines()) <= 70, (path, start)
        return result.stdout, result.stderr

    def events(output):
        return [line.decode() for line in output.splitlines() if line.startswith(b"EVENT ")]

    template = (fixtures / "cases.goose.data").read_text()
    scenarios = {
        "pass": {},
        "setup_hard": {"SETUP_FAILURE": 'if f.id == 1 { t.fail("setup hard"); print("NEVER SETUP"); }'},
        "setup_soft": {"SETUP_FAILURE": 'if f.id == 1 { t.check_eq(1, 2, "setup soft"); print("SOFT CONTINUED"); }'},
        "setup_default": {"SETUP_EARLY": 'if f.id == 1 { t.fail("setup default"); }'},
        "body": {"BODY_FAILURE": 't.fail("body hard"); print("NEVER BODY");'},
        "cleanup": {"CLEANUP_FAILURE": 'if f.id == 1 { t.fail("cleanup hard"); print("NEVER CLEANUP"); }'},
        "body_cleanup": {
            "BODY_FAILURE": 't.fail("body hard"); print("NEVER BODY");',
            "CLEANUP_FAILURE": 'if f.id == 1 { t.fail("cleanup hard"); print("NEVER CLEANUP"); }'},
        "setup_cleanup": {
            "SETUP_FAILURE": 'if f.id == 1 { t.fail("setup hard"); }',
            "CLEANUP_FAILURE": 'if f.id == 1 { t.fail("cleanup hard"); }'},
    }
    for name, changes in scenarios.items():
        source = template
        for key in ("SETUP_EARLY", "SETUP_FAILURE", "BODY_FAILURE", "CLEANUP_FAILURE"):
            source = source.replace(key, changes.get(key, ""))
        setup_failed = name.startswith("setup")
        first_state = 7 if name == "setup_default" else 9 if setup_failed else 11
        # Soft setup continues after its failure; readiness becomes true but body is still skipped.
        ready = not setup_failed or name == "setup_soft"
        source = source.replace("CLEANUP_CHECK",
                                f'if f.id == 1 {{ t.assert_eq({first_state}, f.state); '
                                f't.assert_eq({str(ready).lower()}, f.ready); }} '
                                'else { t.assert_eq(12, f.state); }')
        out, err = run(source, 0 if name == "pass" else 1)
        expected = ["EVENT CONSTRUCT 1", "EVENT SETUP 1"]
        if not setup_failed:
            expected += ["EVENT BODY 1"]
        expected += ["EVENT CLEAN 1", "EVENT FREE 1", "EVENT CONSTRUCT 2",
                     "EVENT SETUP 2", "EVENT SECOND 2", "EVENT CLEAN 2"]
        assert events(out) == expected, (name, events(out), out, err)
        assert b"NEVER" not in out, (name, out)
        assert (b"SOFT CONTINUED" in out) == (name == "setup_soft")
        assert (b"Cases: 3 passed, 0 failed" if name == "pass" else b"Cases: 2 passed, 1 failed") in out
        if setup_failed:
            assert b"[setup]" in out
        if "body" in name:
            assert b"[test]" in out and b"body hard" in out
        if "cleanup" in name:
            assert b"[cleanup]" in out and b"cleanup hard" in out
        if name == "body_cleanup":
            assert out.index(b"[test]") < out.index(b"[cleanup]")
        if name == "setup_cleanup":
            assert out.index(b"[setup]") < out.index(b"[cleanup]")

    legacy = (fixtures / "legacy.goose.data").read_text()
    out, _ = run(legacy, 0)
    assert events(out) == ["EVENT CONSTRUCT 1", "EVENT SETUP", "EVENT BODY", "EVENT CLEAN", "EVENT FREE"]
    assert b"Cases: 2 passed" in out
    for hook in ("before_each", "after_each"):
        mixed_hooks = legacy.replace(f"fn {hook}(f: Fixture&)",
                                     f"fn {hook}(t: goosetest::Test&, f: Fixture&)")
        out, _ = run(mixed_hooks, 0)
        assert events(out) == ["EVENT CONSTRUCT 1", "EVENT SETUP", "EVENT BODY", "EVENT CLEAN", "EVENT FREE"]

    # Missing hooks are optional; default fixture state still belongs to this case.
    before_start = legacy.index("fn before_each")
    after_start = legacy.index("fn after_each")
    body_start = legacy.index("fn test_first")
    without_setup = (legacy[:before_start] + legacy[after_start:]).replace('t.assert_eq(7, f.value)',
                                                                         't.assert_eq(5, f.value)')
    out, _ = run(without_setup, 0)
    assert events(out) == ["EVENT CONSTRUCT 1", "EVENT BODY", "EVENT CLEAN", "EVENT FREE"]
    without_cleanup = legacy[:after_start] + legacy[body_start:]
    out, _ = run(without_cleanup, 0)
    assert events(out) == ["EVENT CONSTRUCT 1", "EVENT SETUP", "EVENT BODY", "EVENT FREE"]
    without_hooks = (legacy[:before_start] + legacy[body_start:]).replace('t.assert_eq(7, f.value)',
                                                                        't.assert_eq(5, f.value)')
    out, _ = run(without_hooks, 0)
    assert events(out) == ["EVENT CONSTRUCT 1", "EVENT BODY", "EVENT FREE"]

    # A suite with hooks but only a Test-only case never constructs or calls them.
    start = legacy.index("fn test_first")
    end = legacy.index("fn test_free")
    free_only = (legacy[:start] + legacy[end:]).replace('t.assert_eq(1, constructed)', 't.assert_eq(0, constructed)')
    out, _ = run(free_only, 0)
    assert events(out) == ["EVENT FREE"], out

    # Both valid hook forms in one suite are ambiguous and fail during discovery.
    duplicate = legacy + '\nfn before_each(t: goosetest::Test&, f: Fixture&) {}\n'
    out, err = run(duplicate, 2)
    assert events(out) == [], out
    assert b"duplicate" in (out + err).lower(), (out, err)

    # Fatal language checks do not unwind into framework cleanup.
    aborting = legacy.replace('t.assert_eq(7, f.value);', 'assert(false);')
    out, err = run(aborting, 2)
    assert events(out) == ["EVENT CONSTRUCT 1", "EVENT SETUP", "EVENT BODY"], (out, err)
    assert b"execution" in err and b"incomplete" in err, err

    # Resource ownership is safe after partial setup and closes an acquired
    # descriptor once after a recoverable body assertion failure.
    (project / "resource.c").write_text(
        '#include <fcntl.h>\n#include <stdio.h>\n#include <unistd.h>\n'
        'static void record(const char *event, int fd) {\n'
        '    FILE *log = fopen("resource-events", "a");\n'
        '    if (!log) _exit(110);\n'
        '    if (fprintf(log, "%s %d\\n", event, fd) < 0 || fclose(log) != 0) _exit(111);\n'
        '}\n'
        'int gt_lifecycle_open_resource(void) {\n'
        '    int fd = open("/dev/null", O_RDONLY);\n'
        '    if (fd >= 0) record("OPEN", fd);\n'
        '    return fd;\n'
        '}\n'
        'int gt_lifecycle_close_resource(int fd) {\n'
        '    record("CLOSE", fd);\n'
        '    return close(fd);\n'
        '}\n')
    (project / "goosetest_root.build").write_text('c_sources = ["resource.c"];\n')
    resource_source = (
        "namespace lifecycle_resource_test;\nimport goosetest;\n"
        'extern "gt_lifecycle_open_resource" fn open_resource() -> i32;\n'
        'extern "gt_lifecycle_close_resource" fn close_resource(fd: i32) -> i32;\n'
        "var next_id: i32 = 0;\n"
        "fn new_id() -> i32 { next_id += 1; return next_id; }\n"
        "struct Fixture { fd: i32 = -1, id: i32 = new_id() }\n"
        "fn before_each(t: goosetest::Test&, f: Fixture&) {\n"
        '    if f.id == 1 { t.fail("partial setup"); }\n'
        "    f.fd = open_resource();\n"
        "    t.assert_true(f.fd >= 0);\n"
        "}\n"
        "fn after_each(t: goosetest::Test&, f: Fixture&) {\n"
        "    if f.fd >= 0 { t.assert_eq(0, close_resource(f.fd)); f.fd = -1; }\n"
        "}\n"
        "fn test_a_partial_setup(t: goosetest::Test&, f: Fixture&) { print(\"NEVER PARTIAL BODY\"); }\n"
        'fn test_b_body_failure(t: goosetest::Test&, f: Fixture&) { t.fail("body failure"); }\n')
    out, err = run(resource_source, 1)
    assert all(value in out for value in (b"[setup]", b"partial setup", b"[test]", b"body failure")), (out, err)
    assert b"NEVER PARTIAL BODY" not in out
    assert (project / "resource-events").read_text().splitlines()[0].startswith("OPEN ")
    resource_events = (project / "resource-events").read_text().splitlines()
    assert len(resource_events) == 2, resource_events
    opened_fd = resource_events[0].split()[1]
    assert resource_events == [f"OPEN {opened_fd}", f"CLOSE {opened_fd}"], resource_events
print("lifecycle process tests passed")
