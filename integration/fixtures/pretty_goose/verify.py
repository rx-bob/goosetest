"""Run original regression contracts, then a disposable mirrored consumer of exact production bytes."""
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
    "integration/pipeline_test.goose::consumer_pipeline_test::test_format_and_lex",
    "test/formatter_test.goose::consumer_formatter_test::test_statement_blocks",
    "test/lexer_test.goose::consumer_lexer_test::test_literal_preservation",
]


def run(argv, cwd, env, status=0):
    result = subprocess.run([str(arg) for arg in argv], cwd=cwd, env=env,
                            capture_output=True, timeout=180)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = json.loads((fixture / "provenance.json").read_text())
for entry in manifest["files"]:
    assert digest(fixture / entry["snapshot"]) == entry["sha256"], entry
# Verify the independent baseline is assembled from exact original declaration bytes.
original_tests = (fixture / "production/original_tests.goose.data").read_text()
declarations = []
for name in manifest["selected_helpers"] + manifest["selected_tests"]:
    start = re.search(r"^fn " + name + r"\(", original_tests, re.M)
    assert start, name
    following = re.search(r"^fn ", original_tests[start.end():], re.M)
    assert following, name
    end = start.end() + following.start()
    declarations.append(original_tests[start.start():end].rstrip() + "\n")
expected_baseline = ("import std;\nimport formatter;\nimport lexer;\n\n"
                     + "\n".join(declarations)
                     + "\nfn main() {\n    test_statement_blocks();\n    test_literal_preservation();\n}\n")
assert (fixture / "baseline.goose.data").read_text() == expected_baseline
with tempfile.TemporaryDirectory(prefix="goosetest-pretty-goose-") as temporary:
    work = Path(temporary).resolve()
    assert work != repo and repo not in work.parents, "consumer workspace must be outside the checkout"
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))
    vendor = work / "vendor"
    vendor.mkdir()
    production = [entry for entry in manifest["files"] if entry["source"] != "tests.goose"]
    for entry in production:
        shutil.copyfile(fixture / entry["snapshot"], vendor / entry["source"])
    (vendor / "pretty_goose.goose").write_text("import lexer;\nimport formatter;\n")
    # Original selected functions and helpers retain builtin assertions and original expectations.
    shutil.copyfile(fixture / "baseline.goose.data", vendor / "baseline.goose")
    baseline = work / "baseline"
    run(["goose", "build", "--debug", vendor / "baseline.goose", "-o", baseline], work, env)
    run([baseline], work, env)
    project = work / "consumer with spaces"
    for template in (fixture / "consumer").rglob("*.goose.data"):
        path = project / template.relative_to(fixture / "consumer")
        path = path.with_suffix("")
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template, path)
    (work / "framework").symlink_to(repo, target_is_directory=True)
    run(["goosefmt", "check", "--config", repo / ".goosefmt.toml", project], work, env)
    listing = run([cli, "list", "--project", project], work, env)
    listed = re.findall(r"^(?:unit|integration)  (\S+)  \(", listing.stdout.decode(), re.M)
    assert listed == EXPECTED, listing.stdout
    assert listing.stdout.decode().endswith("3 discovered cases: 3 executable, 0 disabled\n")
    audit = run([cli, "check-mirror", "--project", project], work, env)
    assert "2 matched" in audit.stdout.decode(), audit.stdout
    result = run([cli, "test", "--project", project], work, env)
    passed = re.findall(r"^PASS (\S+) \(", result.stdout.decode(), re.M)
    assert passed == EXPECTED, result.stdout
    assert "Cases: 3 passed, 0 failed, 0 skipped, 0 errors, 0 not run" in result.stdout.decode()
    run(["goosefmt", "check", "--config", repo / ".goosefmt.toml", project], work, env)
    negative = project / "test/formatter_test.goose"
    original = negative.read_text()
    wrong = original.replace('"fn f() {\\n', '"BROKEN fn f() {\\n', 1)
    assert wrong != original
    negative.write_text(wrong)
    rejected = run([cli, "test", "--project", project], work, env, 1)
    text = rejected.stdout.decode()
    assert re.findall(r"^FAIL (\S+) \(", text, re.M) == [EXPECTED[1]], text
    assert re.findall(r"^PASS (\S+) \(", text, re.M) == [EXPECTED[0], EXPECTED[2]], text
    assert re.search(r"FAIL .* \(test/formatter_test\.goose:[0-9]+\)", text), text
    assert "pretty-goose statement formatting" in text, text
    assert "expected: <BROKEN fn f()" in text and "actual: <fn f()" in text, text
    assert "Cases: 2 passed, 1 failed, 0 skipped, 0 errors, 0 not run" in text, text
    for entry in production:
        assert digest(vendor / entry["source"]) == entry["sha256"], entry
print("pretty-goose adoption passed: original baseline, 3 exact migrated IDs, failing expectation status 1")
