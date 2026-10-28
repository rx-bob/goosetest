"""Verify selected target inventories, stable IDs, and all-target preflight."""
import json
import os
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]


def run(args, cwd, env, status=0, contains=b""):
    result = subprocess.run([cli, *args], cwd=cwd, env=env, capture_output=True, timeout=180)
    assert result.returncode == status, (args, result.returncode, result.stdout, result.stderr)
    assert contains in result.stdout + result.stderr, (contains, result.stdout, result.stderr)
    return result


def suite(namespace, function, assertion="t.assert_true(true);"):
    return (f"namespace {namespace};\nimport goosetest;\n"
            f"fn {function}(t: goosetest::Test&) {{ {assertion} }}\n")


def entry(path, target):
    (path / f"goosetest_{target}.goose").write_text(
        f'import goosetest from "../goosetest";\n'
        f"import goosetest_generated.{target}.runner;\n"
        "fn main() { exit(goosetest_generated::run_all()); }\n")


def artifact_snapshot(directory):
    return {str(path.relative_to(directory)): (path.read_bytes(), path.stat().st_mtime_ns)
            for path in sorted(directory.rglob("*")) if path.is_file()}


def stopped(pid, allow_zombie=False):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    if not allow_zombie:
        return False
    state = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="], capture_output=True,
                           text=True, timeout=3).stdout.strip()
    return not state or state.startswith("Z")


def wait_tree_stopped(pids):
    deadline = time.monotonic() + 5
    while not all(stopped(pid, index > 0) for index, pid in enumerate(pids)):
        assert time.monotonic() < deadline, ("owned process survived", pids)
        time.sleep(.02)


with tempfile.TemporaryDirectory(prefix="goosetest-targets-") as temporary:
    work = Path(temporary)
    project = work / "consumer"
    project.mkdir()
    (work / "goosetest").symlink_to(repo, target_is_directory=True)
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))
    config = {"version": 1, "targets": [
        {"name": "http", "entry": "goosetest_http.goose",
         "tests": [{"path": "tests/http", "kind": "integration"}]},
        {"name": "database", "entry": "missing_database_entry.goose",
         "tests": [{"path": "tests/database", "kind": "integration"}]},
        {"name": "core", "entry": "goosetest_core.goose",
         "tests": [{"path": "tests/core", "kind": "unit"}]},
    ]}
    (project / "goosetest.json").write_text(json.dumps(config))
    (project / "tests/core").mkdir(parents=True)
    (project / "tests/http").mkdir(parents=True)
    (project / "tests/core/path_test.goose").write_text(suite("shared_test", "test_route"))
    (project / "tests/http/path_test.goose").write_text(suite("shared_test", "test_route"))
    entry(project, "core")
    entry(project, "http")

    # Selected inventory ignores the absent database entry and root.
    core = run(["list", "--project", str(project), "--target", "core"], work, env)
    assert core.stdout.startswith(b"unit  core::tests/core/path_test.goose::shared_test::test_route")
    assert b"database::" not in core.stdout
    assert b"http::" not in core.stdout
    core_again = run(["list", "--project", str(project), "--target", "core"], work, env)
    assert core.stdout == core_again.stdout

    # CLI argument order does not control inventory/list ordering or IDs.
    both = run(["list", "--project", str(project), "--target", "http", "--target", "core"], work, env)
    assert both.stdout.index(b"core::") < both.stdout.index(b"http::")
    both_reverse = run(["list", "--project", str(project), "--target", "core", "--target", "http"], work, env)
    assert both.stdout == both_reverse.stdout
    assert both.stdout.count(b"::shared_test::test_route") == 2
    both_run = run(["test", "--project", str(project), "--target", "http", "--target", "core"],
                   work, env, contains=b"1 passed")
    assert both_run.stdout.index(b"PASS core::") < both_run.stdout.index(b"PASS http::")

    # Invalid unselected suites and missing entry files stay outside core preflight.
    (project / "tests/database").mkdir(parents=True)
    (project / "tests/database/bad_test.goose").write_text("namespace broken; fn test_bad(")
    run(["test", "--project", str(project), "--target", "core"], work, env,
        contains=b"1 passed")
    assert not (project / "goosetest_generated/database/tests").exists()

    # A selected invalid suite prevents every selected listing and all builds.
    shutil.rmtree(project / "goosetest_generated")
    invalid_selected = run(["list", "--project", str(project), "--target", "core", "--target", "database"],
                           work, env, 2, b"tests/database")
    assert b"core::" not in invalid_selected.stdout
    assert not (project / "goosetest_generated").exists()

    compiler_called = work / "compiler-called"
    compiler_spy = work / "compiler-spy"
    compiler_spy.write_text(f"#!/bin/sh\nprintf called > '{compiler_called}'\nexit 87\n")
    compiler_spy.chmod(0o755)
    run(["test", "--project", str(project), "--target", "core", "--target", "database",
         "--compiler", str(compiler_spy)], work, env, 2, b"tests/database")
    assert not compiler_called.exists(), "selected-target preflight must finish before compiler spawn"

    # Name validation happens before discovery; unknown, duplicate, and mixed selectors are rejected.
    for selectors in (("--target", "unknown"), ("--target", "core", "--target", "core"),
                      ("--target", "all", "--target", "core")):
        failed = run(["test", "--project", str(project), "--compiler", str(compiler_spy), *selectors],
                     work, env, 2, b"target")
        assert not (project / "goosetest_generated").exists()
        assert not compiler_called.exists()

    # Make database valid but unmatched; core alone matches the filter and builds once.
    config["targets"][1].update(entry="goosetest_database.goose")
    (project / "goosetest_database.goose").write_text(
        'import goosetest from "../goosetest";\n'
        "import goosetest_generated.database.runner;\n"
        "fn main() { exit(goosetest_generated::run_all()); }\n")
    (project / "tests/database/bad_test.goose").write_text(
        "namespace database_test;\nimport goosetest;\n"
        "// @Disabled(\"external database is not installed\")\n"
        "fn test_database(t: goosetest::Test&) { t.fail(\"must remain skipped\"); }\n")
    (project / "goosetest.json").write_text(json.dumps(config))
    all_targets = run(["list", "--project", str(project), "--target", "all"], work, env)
    assert b"core::tests/core/path_test.goose" in all_targets.stdout
    assert b"database::tests/database/bad_test.goose" in all_targets.stdout
    assert b"http::tests/http/path_test.goose" in all_targets.stdout
    integration_targets = run(["list", "--project", str(project), "--target", "all",
                               "--suite", "integration"], work, env)
    assert b"core::" not in integration_targets.stdout
    assert b"database::" in integration_targets.stdout and b"http::" in integration_targets.stdout
    run(["check-mirror", "--project", str(project), "--target", "core"], work, env, 2,
        b"Mirror enforcement is disabled")
    filtered = run(["test", "--project", str(project), "--target", "database", "--target", "core",
                    "--filter", "test_route"], work, env, contains=b"1 passed")
    assert filtered.stdout.index(b"PASS core::") < filtered.stdout.index(b"TARGET database: selection excluded"), (
        filtered.stdout, filtered.stderr)
    assert b"TARGET database PROFILE debug: selection excluded" in filtered.stdout
    assert (project / "goosetest_generated/core/tests").is_file()
    assert not (project / "goosetest_generated/database/tests").exists()

    zero = run(["test", "--project", str(project), "--target", "database", "--filter", "no_match"],
               work, env, 2, b"matched zero cases")
    assert not (project / "goosetest_generated/database/tests").exists()
    disabled = run(["test", "--project", str(project), "--target", "database",
                    "--filter", "::test_database"], work, env, contains=b"1 skipped")
    assert b"SKIP database::tests/database/bad_test.goose::database_test::test_database" in disabled.stdout
    assert b"external database is not installed" in disabled.stdout
    assert b"TARGET database PROFILE debug: skipped (all cases disabled)" in disabled.stdout

    # The real compiler associates a nested entry with its adjacent sidecar and
    # resolves native source paths from that sidecar's directory.
    nested_compiler_project = work / "nested compiler sidecar"
    nested_entry_dir = nested_compiler_project / "targets/core"
    (nested_entry_dir / "native").mkdir(parents=True)
    nested_entry = nested_entry_dir / "goosetest_core.goose"
    nested_entry.write_text(
        'import goosetest from "../../../goosetest";\n'
        'extern "nested_sidecar_value" fn value() -> i64;\n'
        "fn main() { if value() != 42 { exit(1); } }\n")
    nested_sidecar = nested_entry_dir / "goosetest_core.build"
    nested_sidecar.write_text('c_sources = ["native/value.c"];\n')
    nested_source = nested_entry_dir / "native/value.c"
    nested_source.write_text("int nested_sidecar_value(void) { return 42; }\n")
    nested_entry_bytes = nested_entry.read_bytes()
    nested_sidecar_bytes = nested_sidecar.read_bytes()
    nested_source_bytes = nested_source.read_bytes()
    nested_binary = work / "nested-sidecar-test"
    nested_build = subprocess.run(
        ["goose", "build", str(nested_entry), "--debug", "-o", str(nested_binary)],
        cwd=nested_compiler_project, env=env, capture_output=True, timeout=120)
    assert nested_build.returncode == 0, (nested_build.stdout, nested_build.stderr)
    subprocess.run([nested_binary], cwd=nested_compiler_project, env=env, check=True, timeout=30)
    assert nested_entry.read_bytes() == nested_entry_bytes
    assert nested_sidecar.read_bytes() == nested_sidecar_bytes
    assert nested_source.read_bytes() == nested_source_bytes

    # Per-target sidecars own direct native inputs; symbols stay isolated per executable.
    native_project = work / "target sidecar consumer"
    native_project.mkdir()
    native_entries = (native_project / "targets")
    core_dir = native_entries / "core"
    database_dir = native_entries / "database"
    for path in (core_dir / "native", database_dir / "native", native_project / "src/core",
                 native_project / "src/database", native_project / "tests/core",
                 native_project / "tests/database"):
        path.mkdir(parents=True, exist_ok=True)
    config = {"version": 1, "targets": [
        {"name": "core", "entry": "goosetest_core.goose",
         "tests": [{"path": "tests/core", "kind": "unit"}]},
        {"name": "database", "entry": "goosetest_database.goose",
         "tests": [{"path": "tests/database", "kind": "integration"}]},
    ]}
    (native_project / "goosetest.json").write_text(json.dumps(config))
    for target_dir, target in ((core_dir, "core"), (database_dir, "database")):
        (native_project / f"goosetest_{target}.goose").write_text(
            'import goosetest from "../goosetest";\n'
            f"import goosetest_generated.{target}.runner;\n"
            "fn main() { exit(goosetest_generated::run_all()); }\n")
        (native_project / f"src/{target}/production.goose").write_text(
            "namespace production;\n"
            'extern "shared_target_value" fn native_value() -> i64;\n'
            "fn value() -> i64 { return native_value(); }\n")
    (core_dir / "native/shared_symbol.c").write_text(
        "int shared_target_value(void) { return 17; }\n")
    (database_dir / "native/shared_symbol.c").write_text(
        "extern int database_library_value(void);\n"
        "int shared_target_value(void) { return database_library_value(); }\n")
    optional_library = database_dir / "native/unavailable_optional.c"
    optional_library.write_text("/* optional database library is unavailable */\n")
    core_sidecar = native_project / "goosetest_core.build"
    core_sidecar.write_text('c_sources = ["targets/core/native/shared_symbol.c"];\n')
    database_sidecar = native_project / "goosetest_database.build"
    database_sidecar.write_text(
        'c_sources = ["targets/database/native/shared_symbol.c", '
        '"targets/database/native/unavailable_optional.c"];\n')
    (native_project / "tests/core/native_test.goose").write_text(
        "namespace native_test;\nimport goosetest;\nimport src.core.production;\n"
        "fn test_native_value(t: goosetest::Test&) { t.assert_eq(17, production::value()); }\n")
    (native_project / "tests/database/native_test.goose").write_text(
        "namespace native_test;\nimport goosetest;\nimport src.database.production;\n"
        "fn test_native_value(t: goosetest::Test&) { t.assert_eq(29, production::value()); }\n")
    core_entry_before = (native_project / "goosetest_core.goose").read_bytes()
    core_sidecar_before = core_sidecar.read_bytes()
    database_entry_before = (native_project / "goosetest_database.goose").read_bytes()
    unavailable_sidecar_before = database_sidecar.read_bytes()
    core_native_before = (core_dir / "native/shared_symbol.c").read_bytes()
    database_native_before = (database_dir / "native/shared_symbol.c").read_bytes()
    run(["test", "--project", str(native_project), "--target", "core"], work, env,
        contains=b"1 passed")
    core_artifacts = native_project / "goosetest_generated/core"
    core_snapshot = artifact_snapshot(core_artifacts)
    unavailable = run(["test", "--project", str(native_project), "--target", "database"], work, env,
                      status=2, contains=b"compilation for target database")
    assert b"core::" not in unavailable.stdout
    assert artifact_snapshot(core_artifacts) == core_snapshot
    assert not (native_project / "goosetest_generated/database/completion").exists()
    assert database_sidecar.read_bytes() == unavailable_sidecar_before

    optional_library.write_text("int database_library_value(void) { return 29; }\n")
    run(["test", "--project", str(native_project), "--target", "database"], work, env,
        contains=b"1 passed")
    database_artifacts = native_project / "goosetest_generated/database"
    database_snapshot = artifact_snapshot(database_artifacts)
    assert artifact_snapshot(core_artifacts) == core_snapshot
    run(["test", "--project", str(native_project), "--target", "core"], work, env,
        contains=b"1 passed")
    assert artifact_snapshot(database_artifacts) == database_snapshot
    assert (core_artifacts / "tests").is_file()
    assert (core_artifacts / "completion").read_bytes() == b"0\n"
    assert (native_project / "goosetest_core.goose").read_bytes() == core_entry_before
    assert core_sidecar.read_bytes() == core_sidecar_before
    assert (native_project / "goosetest_database.goose").read_bytes() == database_entry_before
    assert database_sidecar.read_bytes() == unavailable_sidecar_before
    assert (database_dir / "native/shared_symbol.c").read_bytes() == database_native_before
    assert (core_dir / "native/shared_symbol.c").read_bytes() == core_native_before

    # Assertion failures continue by default, compile failures continue only
    # after the compiler child was reaped, and aggregate status 2 dominates 1.
    results_project = work / "aggregate outcomes"
    results_project.mkdir()
    result_names = ("core", "database", "http", "tail")
    result_config = {"version": 1, "targets": []}
    for name in result_names:
        (results_project / f"tests/{name}").mkdir(parents=True)
        entry(results_project, name)
        result_config["targets"].append({
            "name": name,
            "entry": f"goosetest_{name}.goose",
            "tests": [{"path": f"tests/{name}", "kind": "unit"}],
        })
    (results_project / "goosetest.json").write_text(json.dumps(result_config))
    (results_project / "tests/core/core_test.goose").write_text(
        suite("core_test", "test_failure", 't.fail("intentional core failure");'))
    (results_project / "tests/database/database_test.goose").write_text(
        suite("database_test", "test_success"))
    (results_project / "tests/http/http_test.goose").write_text(
        suite("http_test", "test_http"))
    (results_project / "tests/tail/tail_test.goose").write_text(
        suite("tail_test", "test_after_compile_failure"))
    (results_project / "goosetest_http.build").write_text('c_sources = ["http.c"];\n')
    (results_project / "http.c").write_text(
        "extern int missing_http_library(void);\n"
        "int http_dependency(void) { return missing_http_library(); }\n")
    invocation_log = work / "compiler-invocations"
    compiler_spy = work / "compiler-spy"
    compiler_spy.write_text(
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        "import os, sys\n"
        f"Path({str(invocation_log)!r}).open('a').write(Path(sys.argv[2]).name + '\\n')\n"
        "os.execvp('goose', ['goose', *sys.argv[1:]])\n")
    compiler_spy.chmod(0o755)

    default_run = run(["test", "--project", str(results_project), "--compiler", str(compiler_spy)],
                      work, env, status=2, contains=b"Aggregate status: 2")
    assert b"TARGET core PROFILE debug: starting" in default_run.stdout
    assert b"TARGET core PROFILE debug: assertion failure (status 1)" in default_run.stdout
    assert b"TARGET database PROFILE debug: passed (status 0)" in default_run.stdout
    assert b"TARGET http PROFILE debug: incomplete (status 2)" in default_run.stdout
    assert b"TARGET tail PROFILE debug: passed (status 0)" in default_run.stdout
    assert invocation_log.read_text().splitlines() == [
        "goosetest_core.goose", "goosetest_database.goose", "goosetest_http.goose",
        "goosetest_tail.goose"]

    invocation_log.unlink()
    fail_fast = run(["test", "--project", str(results_project), "--compiler", str(compiler_spy),
                     "--fail-fast"], work, env, status=1, contains=b"Aggregate status: 1")
    assert invocation_log.read_text().splitlines() == ["goosetest_core.goose"]
    assert b"TARGET database PROFILE debug: NOT RUN" in fail_fast.stdout
    assert b"TARGET http PROFILE debug: NOT RUN" in fail_fast.stdout
    assert b"TARGET tail PROFILE debug: NOT RUN" in fail_fast.stdout

    invocation_log.unlink()
    compile_then_pass = run(["test", "--project", str(results_project), "--compiler", str(compiler_spy),
                             "--target", "http", "--target", "tail"], work, env,
                            status=2, contains=b"Aggregate status: 2")
    assert invocation_log.read_text().splitlines() == ["goosetest_http.goose", "goosetest_tail.goose"]
    assert b"TARGET tail PROFILE debug: passed (status 0)" in compile_then_pass.stdout

    # Each target gets a fresh child and native globals, including after abort().
    isolation = work / "native state isolation"
    isolation.mkdir()
    isolation_names = ("core", "database", "fatal", "tail")
    isolation_config = {"version": 1, "targets": []}
    fixture = Path(__file__).with_name("process_fixture.c")
    shutil.copyfile(fixture, isolation / "process_fixture.c")
    for name in isolation_names:
        (isolation / f"tests/{name}").mkdir(parents=True)
        entry(isolation, name)
        (isolation / f"goosetest_{name}.build").write_text('c_sources = ["process_fixture.c"];\n')
        isolation_config["targets"].append({
            "name": name,
            "entry": f"goosetest_{name}.goose",
            "tests": [{"path": f"tests/{name}", "kind": "unit"}],
        })
        if name == "fatal":
            body = ("assert(fixture_next() == 1); fixture_abort();")
        elif name == "tail":
            body = "assert(fixture_next() == 1); assert(fixture_descendant_stopped() == 1);"
        else:
            body = "assert(fixture_next() == 1);"
        (isolation / f"tests/{name}/{name}_test.goose").write_text(
            f"namespace {name}_test;\nimport goosetest;\n"
            'extern "goosetest_fixture_next" fn fixture_next() -> i32;\n'
            'extern "goosetest_fixture_abort" fn fixture_abort();\n'
            'extern "goosetest_fixture_descendant_stopped" fn fixture_descendant_stopped() -> i32;\n'
            f"fn test_native_state(t: goosetest::Test&) {{ {body} }}\n")
    (isolation / "goosetest.json").write_text(json.dumps(isolation_config))
    observations = isolation / "process-observations"
    isolated_run = run(["test", "--project", str(isolation)], work, env,
                       status=2, contains=b"TARGET tail PROFILE debug: passed (status 0)")
    assert b"TARGET fatal PROFILE debug: incomplete (status 2)" in isolated_run.stdout
    observed = [line.split() for line in observations.read_text().splitlines()]
    assert len(observed) == 4 and all(value == "1" for _, value in observed), observed
    assert len({pid for pid, _ in observed}) == 4, observed

    observations.unlink()
    fatal_fail_fast = run(["test", "--project", str(isolation), "--fail-fast"], work, env,
                           status=2, contains=b"Aggregate status: 2")
    assert observations.read_text().splitlines() and len(observations.read_text().splitlines()) == 3
    assert b"TARGET tail PROFILE debug: NOT RUN" in fatal_fail_fast.stdout

    # Stale success is reset before explicit exit(0)/exit(1), and malformed
    # completion evidence is rejected even when the generated runner passed.
    evidence = work / "completion evidence"
    evidence.mkdir()
    (evidence / "tests/case").mkdir(parents=True)
    entry(evidence, "evidence")
    (evidence / "tests/case/evidence_test.goose").write_text(
        suite("evidence_test", "test_valid_completion"))
    (evidence / "goosetest.json").write_text(json.dumps({"version": 1, "targets": [{
        "name": "evidence", "entry": "goosetest_evidence.goose",
        "tests": [{"path": "tests/case", "kind": "unit"}],
    }]}))
    run(["test", "--project", str(evidence)], work, env,
        contains=b"TARGET evidence PROFILE debug: passed (status 0)")
    assert (evidence / "goosetest_generated/evidence/completion").read_bytes() == b"0\n"
    evidence_entry = evidence / "goosetest_evidence.goose"
    for code in (0, 1):
        evidence_entry.write_text(f"fn main() {{ exit({code}); }}\n")
        early_exit = run(["test", "--project", str(evidence)], work, env, status=2,
                         contains=b"completion record")
        assert b"TARGET evidence PROFILE debug: incomplete (status 2)" in early_exit.stdout
        assert b"TARGET evidence PROFILE debug: passed" not in early_exit.stdout
        assert not (evidence / "goosetest_generated/evidence/completion").exists()

    evidence_entry.write_text(
        'import goosetest from "../goosetest";\n'
        "import goosetest_generated.evidence.runner;\n"
        'extern "goosetest_fixture_corrupt_completion" fn corrupt_completion();\n'
        "fn main() { let status = goosetest_generated::run_all(); corrupt_completion(); exit(status); }\n")
    (evidence / "process_fixture.c").write_bytes(fixture.read_bytes())
    (evidence / "goosetest_evidence.build").write_text('c_sources = ["process_fixture.c"];\n')
    malformed_env = dict(env, GOOSETEST_COMPLETION_PATH=str(
        evidence / "goosetest_generated/evidence/completion"))
    malformed = run(["test", "--project", str(evidence)], work, malformed_env, status=2,
                    contains=b"completion record")
    assert b"TARGET evidence PROFILE debug: incomplete (status 2)" in malformed.stdout
    assert (evidence / "goosetest_generated/evidence/completion").read_bytes() == b"bad\n"

    # A run deadline must release a descendant-owned listening socket before
    # the next target begins and default mode must continue to that target.
    timeout_project = work / "target timeout socket"
    timeout_project.mkdir()
    shutil.copyfile(fixture, timeout_project / "process_fixture.c")
    timeout_config = {"version": 1, "targets": []}
    for name in ("alpha", "beta"):
        (timeout_project / f"tests/{name}").mkdir(parents=True)
        entry(timeout_project, name)
        (timeout_project / f"goosetest_{name}.build").write_text('c_sources = ["process_fixture.c"];\n')
        timeout_config["targets"].append({
            "name": name,
            "entry": f"goosetest_{name}.goose",
            "tests": [{"path": f"tests/{name}", "kind": "unit"}],
        })
    (timeout_project / "goosetest.json").write_text(json.dumps(timeout_config))
    (timeout_project / "tests/alpha/alpha_test.goose").write_text(
        'namespace alpha_test;\nimport goosetest;\n'
        'extern "goosetest_fixture_socket_wait" fn socket_wait();\n'
        "fn test_socket_owner(t: goosetest::Test&) { socket_wait(); }\n")
    (timeout_project / "tests/beta/beta_test.goose").write_text(
        'namespace beta_test;\nimport goosetest;\n'
        'extern "goosetest_fixture_rebind_socket" fn rebind_socket() -> i32;\n'
        "fn test_socket_released(t: goosetest::Test&) { t.assert_eq(1, rebind_socket()); }\n")
    timed_out = run(["test", "--project", str(timeout_project), "--run-timeout-seconds", "1"],
                    work, env, status=2, contains=b"TARGET beta PROFILE debug: passed (status 0)")
    assert b"TARGET alpha PROFILE debug: incomplete (status 2)" in timed_out.stdout
    timeout_pids = [int(value) for value in (timeout_project / "owned-pids").read_text().split()]
    wait_tree_stopped(timeout_pids)

    # Interrupt both the first and a later selected target with SIGINT/SIGTERM.
    # The cancelled invocation must skip gamma and release the lock for reuse.
    cancel_project = work / "target cancellation"
    cancel_project.mkdir()
    shutil.copyfile(fixture, cancel_project / "process_fixture.c")
    cancel_config = {"version": 1, "targets": []}
    for name in ("alpha", "beta", "gamma"):
        (cancel_project / f"tests/{name}").mkdir(parents=True)
        entry(cancel_project, name)
        cancel_config["targets"].append({
            "name": name,
            "entry": f"goosetest_{name}.goose",
            "tests": [{"path": f"tests/{name}", "kind": "unit"}],
        })
    (cancel_project / "goosetest.json").write_text(json.dumps(cancel_config))
    (cancel_project / "tests/alpha/alpha_test.goose").write_text(
        suite("alpha_test", "test_before_cancel"))
    (cancel_project / "goosetest_beta.build").write_text('c_sources = ["process_fixture.c"];\n')
    (cancel_project / "tests/beta/beta_test.goose").write_text(
        'namespace beta_test;\nimport goosetest;\n'
        'extern "goosetest_fixture_socket_wait" fn socket_wait();\n'
        "fn test_wait_for_cancellation(t: goosetest::Test&) { socket_wait(); }\n")
    (cancel_project / "tests/gamma/gamma_test.goose").write_text(
        'namespace gamma_test;\nimport goosetest;\nimport os;\n'
        'fn test_must_not_run(t: goosetest::Test&) { t.assert_true(write_file("gamma-ran", "yes")); }\n')

    for selected_first in (True, False):
        for cancel_signal in (signal.SIGINT, signal.SIGTERM):
            (cancel_project / "gamma-ran").unlink(missing_ok=True)
            (cancel_project / "owned-pids").unlink(missing_ok=True)
            (cancel_project / "owned-port").unlink(missing_ok=True)
            selectors = ["--target", "beta", "--target", "gamma"] if selected_first else []
            command = [cli, "test", "--project", str(cancel_project), "--run-timeout-seconds", "30",
                       *selectors]
            running = subprocess.Popen(command, cwd=work, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE)
            try:
                ready_by = time.monotonic() + 40
                while not (cancel_project / "owned-pids").exists():
                    assert running.poll() is None, running.communicate()
                    assert time.monotonic() < ready_by, "target process tree did not become ready"
                    time.sleep(.02)
                cancelled_pids = [int(value) for value in
                                  (cancel_project / "owned-pids").read_text().split()]
                running.send_signal(cancel_signal)
                stdout, stderr = running.communicate(timeout=20)
                expected = 128 + cancel_signal
                assert running.returncode == expected, (running.returncode, stdout, stderr)
                assert f"Aggregate status: {expected}".encode() in stdout, stdout
                assert f"signal={cancel_signal}".encode() in stderr and b"run incomplete" in stderr, stderr
                assert b"TARGET beta PROFILE debug: cancelled" in stdout, stdout
                assert b"TARGET gamma PROFILE debug: NOT RUN" in stdout, stdout
                if not selected_first:
                    assert b"TARGET alpha PROFILE debug: passed" in stdout, stdout
                assert not (cancel_project / "gamma-ran").exists()
                wait_tree_stopped(cancelled_pids)
            finally:
                if running.poll() is None:
                    running.kill()
                    running.communicate(timeout=5)

            # A fresh command proves cancellation closed the project lock.
            reacquired = run(["test", "--project", str(cancel_project), "--target", "gamma"],
                             work, env, contains=b"TARGET gamma PROFILE debug: passed (status 0)")
            assert b"1 passed" in reacquired.stdout
            assert (cancel_project / "gamma-ran").read_text() == "yes"

print("target selection and preflight tests passed")
