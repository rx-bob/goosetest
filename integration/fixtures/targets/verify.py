"""Verify selected target inventories, stable IDs, and all-target preflight."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

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
    assert filtered.stdout.index(b"TARGET database: selection excluded") < filtered.stdout.index(b"PASS core::"), (
        filtered.stdout, filtered.stderr)
    assert (project / "goosetest_generated/core/tests").is_file()
    assert not (project / "goosetest_generated/database/tests").exists()

    zero = run(["test", "--project", str(project), "--target", "database", "--filter", "no_match"],
               work, env, 2, b"matched zero cases")
    assert not (project / "goosetest_generated/database/tests").exists()
    disabled = run(["test", "--project", str(project), "--target", "database",
                    "--filter", "::test_database"], work, env, contains=b"1 skipped")
    assert b"SKIP database::tests/database/bad_test.goose::database_test::test_database" in disabled.stdout
    assert b"external database is not installed" in disabled.stdout

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

print("target selection and preflight tests passed")
