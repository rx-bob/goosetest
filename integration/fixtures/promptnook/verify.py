"""Verify a Promptnook-shaped domain/native split without application services."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
fixture = Path(__file__).resolve().parent
repo = fixture.parents[2]
DOMAIN_ID = (
    "core::tests/core/workspace_tree_test.goose::workspace_tree_test::"
    "test_workspace_tree_order_and_nesting"
)
DATABASE_ID = "database::tests/database/native_state_test.goose::native_state_test::test_native_resource_is_open_during_body"
RESOURCE = "db/goosetest-owned.fixture"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv, cwd, env, status=0):
    result = subprocess.run([str(value) for value in argv], cwd=cwd, env=env,
                            capture_output=True, timeout=240)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result


def materialize_templates(source, destination):
    for template in sorted(source.rglob("*.data")):
        path = destination / template.relative_to(source)
        path = path.with_suffix("")
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template, path)


def append_snapshot(project, template, snapshot):
    target = project / template
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(target.read_bytes() + (fixture / snapshot).read_bytes())


manifest = json.loads((fixture / "provenance.json").read_text())
for record in manifest["snapshots"]:
    assert digest(fixture / record["snapshot"]) == record["sha256"], record

with tempfile.TemporaryDirectory(prefix="goosetest-promptnook-adoption-") as temporary:
    work = Path(temporary).resolve()
    project = work / "promptnook-shaped consumer"
    project.mkdir()
    (work / "goosetest").symlink_to(repo, target_is_directory=True)
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))

    # Keep application-shaped paths at project root; only selected pure source
    # declarations are snapshotted into these modules.
    materialize_templates(fixture / "consumer", project)
    (project / "users").mkdir()
    append_snapshot(project, "workspaces/tree.goose", "production/workspaces/tree.goose.data")
    append_snapshot(project, "mcp_protocol/json_parser.goose", "production/mcp_protocol/json_member_last.goose.data")
    (project / "goosetest.json").write_text(json.dumps({
        "version": 1,
        "targets": [
            {"name": "core", "entry": "goosetest_core.goose",
             "tests": [{"path": "tests/core", "kind": "unit"}],
             "mirror": {"policy": "off", "pairs": []}},
            {"name": "database", "entry": "goosetest_database.goose",
             "tests": [{"path": "tests/database", "kind": "integration"}],
             "mirror": {"policy": "off", "pairs": []}},
        ],
    }))

    assert all((project / path).is_dir() for path in ("users", "workspaces", "db", "tests/core", "tests/database"))
    listed = run([cli, "list", "--project", project, "--target", "core"], work, env)
    ids = re.findall(r"^(?:unit|integration)  (\S+)  \(", listed.stdout.decode(), re.M)
    assert ids == [DOMAIN_ID], listed.stdout

    # Core remains independent from the deliberately absent database link input.
    for profile in ("debug", "optimized"):
        args = [cli, "test", "--project", project, "--target", "core", "--profile", profile]
        if profile == "optimized":
            args.append("--offline")
        result = run(args, work, env)
        assert f"PASS {DOMAIN_ID} (".encode() in result.stdout, (profile, result.stdout)
        assert b"1 passed, 0 failed" in result.stdout
        assert not (project / "goosetest_generated/database/tests").exists()
        assert not (project / RESOURCE).exists()

    missing = run([cli, "test", "--project", project, "--target", "database", "--profile", "debug"],
                  work, env, 2)
    assert b"compilation for target database" in missing.stderr, missing.stderr
    assert b"unavailable_libsql.c" in missing.stderr, missing.stderr
    assert not (project / "goosetest_generated/database/completion").exists()

    # This placeholder satisfies only the stand-in's optional link boundary; it
    # is not libSQL and the test never imports or calls Promptnook database code.
    optional_source = project / "db/unavailable_libsql.c"
    optional_source.write_text("int pn_fixture_optional_database_link(void) { return 1; }\n")
    for invocation in range(2):
        result = run([cli, "test", "--project", project, "--target", "database", "--profile", "debug"],
                     work, env)
        assert f"PASS {DATABASE_ID} (".encode() in result.stdout, (invocation, result.stdout)
        assert b"1 passed, 0 failed" in result.stdout
        assert not (project / RESOURCE).exists(), "database fixture must remove its owned resource"

    # Core can be rerun after the database target without importing its sidecar.
    run([cli, "test", "--project", project, "--target", "core", "--profile", "optimized", "--offline"],
        work, env)
    assert not (project / RESOURCE).exists()

print("Promptnook-shaped adoption passed: unchanged tree behavior, core/database isolation, fresh native state, owned resource cleanup")
