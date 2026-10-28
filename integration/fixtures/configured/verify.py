"""Exercise the configured one-target pipeline from an unrelated caller cwd."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]


def write_project(root, suite=None, entry=None):
    tests = root / "tests/request"
    tests.mkdir(parents=True)
    (tests / "support.goose").write_text(
        "namespace support;\nfn value() -> i64 { return 42; }\n")
    (root / "resource").write_text("project cwd\n")
    if suite is None:
        suite = (
            "namespace url_test;\nimport goosetest;\nimport os;\nimport tests.request.support;\n"
            "fn test_a_failure(t: goosetest::Test&) { t.assert_eq(1, 2); }\n"
            "fn test_b_pass(t: goosetest::Test&) { var data: u8[>..] = []; "
            "t.assert_true(read_file(\"resource\", data)); t.assert_eq(\"project cwd\\n\", data); "
            "t.assert_eq(42, support::value()); }\n")
    (tests / "url_test.goose").write_text(suite)
    if entry is None:
        entry = (
            'import goosetest from "../goosetest";\n'
            "import goosetest_generated.core.runner;\n"
            "fn main() { exit(goosetest_generated::run_all()); }\n")
    (root / "goosetest_core.goose").write_text(entry)
    config = {
        "version": 1,
        "targets": [{
            "name": "core",
            "entry": "goosetest_core.goose",
            "tests": [{"path": "tests/request", "kind": "unit"}],
            "mirror": {"policy": "off", "pairs": []},
        }],
    }
    (root / "goosetest.json").write_text(json.dumps(config))


def run(args, cwd, status=0, contains=b""):
    result = subprocess.run([cli, *args], cwd=cwd, env=env, capture_output=True, timeout=180)
    assert result.returncode == status, (args, result.returncode, result.stdout, result.stderr)
    assert contains in result.stdout + result.stderr, (contains, result.stdout, result.stderr)
    return result


def project(base, name):
    root = base / name
    root.mkdir()
    link = base / "goosetest"
    if not link.exists():
        link.symlink_to(repo, target_is_directory=True)
    write_project(root)
    native = root / "native"
    native.mkdir()
    (native / "marker.c").write_text("int configured_marker(void) { return 1; }\n")
    (root / "goosetest_core.build").write_text('c_sources = ["native/marker.c"];\n')
    return root


with tempfile.TemporaryDirectory(prefix="goosetest-configured-") as temporary:
    work = Path(temporary)
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))
    # Run from another cwd: the config, entry, generated imports, and test resource all
    # resolve from the project root.
    good = project(work, "consumer with spaces")
    before_entry = (good / "goosetest_core.goose").read_bytes()
    before_sidecar = (good / "goosetest_core.build").read_bytes()
    listed = run(["list", "--project", str(good)], work, contains=b"core::tests/request/url_test.goose::url_test::test_a_failure")
    assert b"core::tests/request/url_test.goose::url_test::test_b_pass" in listed.stdout
    assert b"support.goose" not in listed.stdout
    run(["check-mirror", "--project", str(good)], work, 2, b"Mirror enforcement is disabled")
    failed = run(["test", "--project", str(good)], work, 1, b"core::tests/request/url_test.goose::url_test::test_a_failure")
    assert b"core::tests/request/url_test.goose::url_test::test_b_pass" in failed.stdout
    assert b"expected: <1> actual: <2>" in failed.stdout
    assert (good / "goosetest_core.goose").read_bytes() == before_entry
    assert (good / "goosetest_core.build").read_bytes() == before_sidecar
    generated = good / "goosetest_generated/core"
    assert (generated / "tests").is_file()
    assert (generated / "completion").read_text() == "1\n"
    run(["test", "--project", str(good)], work, 1, b"1 failed")
    first = {path.name: (hashlib.sha256(path.read_bytes()).digest(), path.stat().st_mtime_ns)
             for path in generated.glob("*.goose")}
    run(["test", "--project", str(good)], work, 1, b"1 failed")
    repeated = {path.name: (hashlib.sha256(path.read_bytes()).digest(), path.stat().st_mtime_ns)
                for path in generated.glob("*.goose")}
    assert first == repeated, (first, repeated)
    (good / "goosetest_generated/user-file.txt").write_text("preserve\n")
    # A later passing case demonstrates normal success after the failure.
    (good / "tests/request/url_test.goose").write_text(
        "namespace url_test;\nimport goosetest;\nimport os;\nimport tests.request.support;\n"
        "fn test_a_pass(t: goosetest::Test&) { var data: u8[>..] = []; "
        "t.assert_true(read_file(\"resource\", data)); t.assert_eq(\"project cwd\\n\", data); "
        "t.assert_eq(42, support::value()); }\n"
        "fn test_b_pass(t: goosetest::Test&) { t.assert_eq(42, support::value()); }\n")
    run(["test", "--project", str(good)], work, contains=b"2 passed")
    assert (good / "goosetest_generated/user-file.txt").read_text() == "preserve\n"

    text = (good / "tests/request/url_test.goose").read_text().replace(
        "tests.request.support", "tests.request.absent")
    (good / "tests/request/url_test.goose").write_text(text)
    run(["test", "--project", str(good)], work, 2, b"compilation")
    assert not (good / "goosetest_generated/core/tests").exists()

    premature = project(work, "premature exit")
    (premature / "goosetest_core.goose").write_text("fn main() { exit(0); }\n")
    run(["test", "--project", str(premature)], work, 2, b"completion record")

    unowned = project(work, "unowned target")
    (unowned / "goosetest_generated/core").mkdir(parents=True)
    run(["test", "--project", str(unowned)], work, 2, b"artifacts")

    linked = project(work, "linked target")
    outside = work / "outside"
    outside.mkdir()
    (linked / "goosetest_generated").mkdir()
    os.symlink(outside, linked / "goosetest_generated/core")
    run(["test", "--project", str(linked)], work, 2, b"artifacts")

    multiple = project(work, "multiple targets")
    config = json.loads((multiple / "goosetest.json").read_text())
    second = dict(config["targets"][0])
    second.update(name="other", entry="other.goose", tests=[{"path": "tests/other", "kind": "unit"}])
    config["targets"].append(second)
    (multiple / "goosetest.json").write_text(json.dumps(config))
    selected = run(["list", "--project", str(multiple), "--target", "core"], work,
                   contains=b"core::tests/request/url_test.goose")
    assert b"other::" not in selected.stdout

    # A configured strict pair uses arbitrary source/test roots and still
    # discovers imported helpers without admitting them as suites.
    strict = project(work, "strict configured mirror")
    (strict / "src/request").mkdir(parents=True)
    (strict / "src/request/url.goose").write_text(
        "namespace url;\nfn value() -> i64 { return 42; }\n")
    (strict / "tests/request/url_test.goose").write_text(
        "namespace url_test;\nimport goosetest;\nimport src.request.url;\n"
        "import tests.request.support;\n"
        "fn test_configured_mirror(t: goosetest::Test&) { "
        "t.assert_eq(42, url::value()); t.assert_eq(42, support::value()); }\n")
    config = json.loads((strict / "goosetest.json").read_text())
    config["targets"][0]["mirror"] = {
        "policy": "strict", "pairs": [{"source": "src/request", "tests": "tests/request"}]
    }
    (strict / "goosetest.json").write_text(json.dumps(config))
    strict_audit = run(["check-mirror", "--project", str(strict), "--target", "core"],
                       work, contains=b"1 matched")
    assert b"Mirror enforcement is disabled" not in strict_audit.stdout
    run(["test", "--project", str(strict), "--target", "core"], work,
        contains=b"1 passed")

print("configured target process tests passed")
