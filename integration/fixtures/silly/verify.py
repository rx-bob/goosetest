"""Compare preserved Silly URL/HTTP checks with a configured goosetest consumer."""
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
EXPECTED = [
    "core::tests/http/http_host_test.goose::http_host_test::test_invalid_authority_forms",
    "core::tests/http/http_host_test.goose::http_host_test::test_request_target_syntax",
    "core::tests/http/http_host_test.goose::http_host_test::test_valid_authority_forms",
    "core::tests/request/url_test.goose::url_test::test_literal_invalid_escapes",
    "core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity",
    "core::tests/request/url_test.goose::url_test::test_strict_query_decoding",
]


def run(argv, cwd, env, status=0):
    result = subprocess.run([str(value) for value in argv], cwd=cwd, env=env,
                            capture_output=True, timeout=240)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def materialize_templates(source, destination):
    for template in sorted(source.rglob("*.data")):
        path = destination / template.relative_to(source)
        path = path.with_suffix("")
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template, path)


manifest = json.loads((fixture / "provenance.json").read_text())
for record in manifest["files"]:
    assert digest(fixture / record["snapshot"]) == record["sha256"], record

with tempfile.TemporaryDirectory(prefix="goosetest-silly-adoption-") as temporary:
    work = Path(temporary).resolve()
    assert work != repo and repo not in work.parents, "consumer workspace must be outside the checkout"
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))

    # Run the original standalone source unchanged, assembled from the exact
    # production and test snapshots recorded above.
    baseline = work / "original Silly baseline"
    production = [record for record in manifest["files"] if record["source"].startswith("src/")]
    original_tests = [record for record in manifest["files"] if record["source"].startswith("tests/")]
    for record in production + original_tests:
        output = baseline / record["source"]
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture / record["snapshot"], output)
    (baseline / "silly.goose").write_text(
        "namespace silly;\n"
        "import.src.request.url;\n"
        "import.src.request.headers;\n"
        "import.src.http.http_host;\n"
        "import.src.http.http_head_types;\n"
        "import.src.http.http_request_line;\n")

    for profile, flags in (("debug", ["--debug"]), ("optimized", ["-O2"])):
        url_binary = work / f"url-original-{profile}"
        http_binary = work / f"http-original-{profile}"
        run(["goose", "build", baseline / "tests/request/url_test.goose", *flags,
             "-o", url_binary], baseline, env)
        url_run = run([url_binary], baseline, env)
        assert url_run.stdout.strip() == b"bounded URL and strict path decoding passed", url_run.stdout
        run(["goose", "build", baseline / "tests/http/http_host_test.goose", *flags,
             "-o", http_binary], baseline, env)
        http_run = run([http_binary], baseline, env)
        assert http_run.stdout.strip() == b"HTTP authority syntax passed", http_run.stdout

    # Materialize the small unchanged package closure and converted test roots.
    project = work / "consumer with spaces"
    for record in production:
        relative = Path(record["source"])
        output = project / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture / record["snapshot"], output)
    materialize_templates(fixture / "consumer", project)
    (work / "goosetest").symlink_to(repo, target_is_directory=True)
    config = {
        "version": 1,
        "targets": [
            {
                "name": "core",
                "entry": "goosetest_core.goose",
                "tests": [
                    {"path": "tests/request", "kind": "unit"},
                    {"path": "tests/http", "kind": "unit"},
                ],
                "mirror": {"policy": "off", "pairs": []},
            },
            {
                "name": "optional_native",
                "entry": "goosetest_optional_native.goose",
                "tests": [{"path": "tests/optional", "kind": "unit"}],
                "mirror": {"policy": "off", "pairs": []},
            },
        ],
    }
    (project / "goosetest.json").write_text(json.dumps(config))

    listed = run([cli, "list", "--project", project, "--target", "core"], work, env)
    listed_ids = re.findall(r"^(?:unit|integration)  (\S+)  \(", listed.stdout.decode(), re.M)
    assert listed_ids == EXPECTED, listed.stdout
    assert listed.stdout.decode().endswith("6 discovered cases: 6 executable, 0 disabled\n")
    disabled_mirror = run([cli, "check-mirror", "--project", project, "--target", "core"],
                          work, env, 2)
    assert b"Mirror enforcement is disabled" in disabled_mirror.stdout + disabled_mirror.stderr

    for profile in ("debug", "optimized"):
        result = run([cli, "test", "--project", project, "--target", "core", "--profile", profile],
                     work, env)
        passed = re.findall(r"^PASS (\S+) \(", result.stdout.decode(), re.M)
        assert passed == EXPECTED, (profile, result.stdout)
        assert "Cases: 6 passed, 0 failed, 0 skipped, 0 errors, 0 not run" in result.stdout.decode()

    # The intentionally unavailable native dependency is outside core's build closure.
    assert not (project / "goosetest_generated/optional_native/tests").exists()
    optional = run([cli, "test", "--project", project, "--target", "optional_native"], work, env, 2)
    assert b"compilation for target optional_native" in optional.stderr, optional.stderr
    assert b"TARGET core" not in optional.stdout

    # A wrong converted expectation remains an ordinary, useful assertion failure.
    url_test = project / "tests/request/url_test.goose"
    original = url_test.read_text()
    wrong = original.replace(
        't.assert_eq("a+b/%2F//", copy(output), "path preserves plus and decodes once");',
        't.assert_eq("BROKEN", copy(output), "path preserves plus and decodes once");', 1)
    assert wrong != original
    url_test.write_text(wrong)
    rejected = run([cli, "test", "--project", project, "--target", "core"], work, env, 1)
    failure_text = rejected.stdout.decode()
    failing_id = "core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity"
    assert re.findall(r"^FAIL (\S+) \(", failure_text, re.M) == [failing_id], failure_text
    assert "path preserves plus and decodes once" in failure_text, failure_text
    assert "expected: <BROKEN>" in failure_text and "actual: <a+b/%2F//>" in failure_text, failure_text
    url_test.write_text(original)

    # Copied production inputs and original test snapshots remain byte-identical.
    for record in production:
        assert digest(project / record["source"]) == record["sha256"], record
        assert digest(baseline / record["source"]) == record["sha256"], record
    for record in original_tests:
        assert digest(baseline / record["source"]) == record["sha256"], record

print("Silly adoption passed: original URL/HTTP checks, six exact IDs in both profiles, optional native isolation")
