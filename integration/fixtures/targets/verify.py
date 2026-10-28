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

print("target selection and preflight tests passed")
