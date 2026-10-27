"""Compile generated consumers without rewriting authored package roots or sidecars."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

generator = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]


def call(args, cwd, environment, status=0):
    result = subprocess.run(args, cwd=cwd, env=environment, capture_output=True, timeout=120)
    assert result.returncode == status, (args, result.stdout.decode(errors="replace"), result.stderr.decode(errors="replace"))
    return result.stdout


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in sorted(directory.rglob("*")) if p.is_file()}


def style(directory, env):
    call(["goosefmt", "check", "--config", str(repo / ".goosefmt.toml"), str(directory)], repo, env)
    for path in directory.glob("*.goose"):
        lines = path.read_text().splitlines()
        assert len(lines) <= 500, path
        starts = [i for i, line in enumerate(lines) if line.startswith("fn ")] + [len(lines)]
        for start, end in zip(starts, starts[1:]):
            assert len("\n".join(lines[start:end]).rstrip().splitlines()) <= 70, (path, start)
        assert all(len(line) <= 120 for line in lines), path


def generate(project, env):
    destination = project / "goosetest_generated"
    if destination.exists():
        shutil.rmtree(destination)
    call([generator, str(project), str(destination)], project.parent, env)
    style(destination, env)
    second = project.parent / "second-generation"
    if second.exists():
        shutil.rmtree(second)
    call([generator, str(project), str(second)], project.parent, env)
    assert snapshot(destination) == snapshot(second)


def build_run(project, work, env, name, status=0):
    binary = work / name
    call(["goose", "build", "--debug", str(project / "goosetest_root.goose"), "-o", str(binary)], work, env)
    return call([str(binary)], work, env, status).decode()


def literal(data):
    return '"' + ''.join(f"\\x{byte:02X}" for byte in data) + '"'


with tempfile.TemporaryDirectory(prefix="goosetest-generation-") as temporary:
    work = Path(temporary).resolve()
    env = dict(os.environ, GOOSE_HOME=str(work / "cache"))
    project = work / "consumer with spaces"
    shutil.copytree(repo / "examples/basic", project)
    (work / "package").symlink_to(repo, target_is_directory=True)
    root = project / "goosetest_root.goose"
    root.write_text('// Authored once.\nimport goosetest from "../package";\n'
                    'import addon from "../native library";\n\nimport goosetest_generated.runner;\n\n'
                    'fn main() {\n    exit(goosetest_generated::run_all());\n}\n')
    addon = work / "native library"
    (addon / "native").mkdir(parents=True)
    (addon / "addon.goose").write_text('namespace addon;\nextern "addon_value" fn value() -> i32;\n')
    (addon / "addon.build").write_text('c_sources = ["native/addon_value.c"];\n')
    (addon / "native/addon_value.c").write_text('#include <stdint.h>\nint32_t addon_value(void) { return 40; }\n')
    (project / "native").mkdir()
    (project / "native/root_value.c").write_text('#include <stdint.h>\nint32_t root_value(void) { return 2; }\n')
    sidecar = project / "goosetest_root.build"
    sidecar.write_text('c_sources = ["native/root_value.c"];\n')
    authored = root.read_bytes(), sidecar.read_bytes(), snapshot(addon)
    generate(project, env)
    output = build_run(project, work, env, "basic")
    assert output.count("PASS ") == 3 and "Cases: 3 passed" in output
    # New valid source/unit pair and integration suite: no root or registration edits.
    (project / "src/native.goose").write_text('namespace native_source;\nimport addon;\n'
        'extern "root_value" fn root_value() -> i32;\nfn value() -> i32 { return addon::value() + root_value(); }\n')
    (project / "test/native_test.goose").write_text('namespace native_test;\nimport goosetest;\nimport src.native;\n'
        'fn test_native(t: goosetest::Test&) { t.assert_eq(42, native_source::value()); }\n')
    (project / "integration").mkdir()
    label = b'quote" slash\\ newline\n nul\x00 utf8\xc3\xa9'
    (project / "integration/label_test.goose").write_text('namespace label_test;\nimport goosetest;\n'
        '// @DisplayName(' + literal(label) + ')\nfn test_label(t: goosetest::Test&) {\n'
        '    let identity = t.results.cases[t.current_case].identity;\n'
        '    t.assert_eq(' + literal(label) + ', goosetest::metadata_text(t.results, identity.display_name));\n}\n')
    with (project / "integration/label_test.goose").open("a") as stream:
        stream.write('// @DisplayName(' + literal(bytes([1]) * 1024) + ')\n'
            'fn test_long_label(t: goosetest::Test&) {\n'
            '    let identity = t.results.cases[t.current_case].identity;\n'
            '    let label = goosetest::metadata_text(t.results, identity.display_name);\n'
            '    t.assert_eq(1024, label.len);\n'
            '    for byte in label { t.assert_eq(1 as u8, byte); }\n}\n')
    generate(project, env)
    output = build_run(project, work, env, "native-and-label")
    assert output.count("PASS ") == 6 and "Cases: 6 passed" in output
    assert authored == (root.read_bytes(), sidecar.read_bytes(), snapshot(addon))
    # Hard failure preserves original attribution and still runs later cases once.
    failed = project / "test/native_test.goose"
    failed.write_text(failed.read_text().replace('t.assert_eq(42, native_source::value());',
                     't.assert_eq(99, native_source::value()); print("NEVER");'))
    failed.write_text(failed.read_text().replace('import src.native;', 'import src.native;\nimport std;'))
    generate(project, env)
    output = build_run(project, work, env, "failure", 1)
    assert "FAIL test/native_test.goose::native_test::test_native (test/native_test.goose:5)" in output
    assert "expected: <99>" in output and "actual: <42>" in output and "NEVER" not in output, output
    # Large fixture crosses old case/file caps and forces two dispatch levels.
    large = work / "large project"
    (large / "src").mkdir(parents=True)
    (large / "test").mkdir()
    (large / "goosetest_root.goose").write_bytes(root.read_bytes())
    expected = []
    for module in range(7):
        (large / f"src/m{module}.goose").write_text(f"namespace source_{module};\n")
        body = f"namespace tests_{module};\nimport goosetest;\nimport std;\n"
        for case in range(50):
            name = f"test_{case}"
            body += f'fn {name}(t: goosetest::Test&) {{ print("VISIT {module}:{case}"); t.assert_true(true); }}\n'
            expected.append(f"VISIT {module}:{case}")
        (large / f"test/m{module}_test.goose").write_text(body)
    generate(large, env)
    assert (large / "goosetest_generated/dispatch_1_0.goose").exists()
    output = build_run(large, work, env, "large")
    assert [line for line in output.splitlines() if line.startswith("VISIT ")] == expected
    assert output.count("PASS ") == 350 and "Cases: 350 passed" in output
    assert authored == (root.read_bytes(), sidecar.read_bytes(), snapshot(addon))
print("generation compile tests passed")
