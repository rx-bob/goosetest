"""Independent profile argv, child-environment, and native-cache oracle."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
repo = Path(__file__).resolve().parents[3]
real_goose = shutil.which("goose")
assert real_goose
CALLER_HOME = "/caller Goose cache ;$(literal)"


def run(args, cwd, env, status=0):
    result = subprocess.run([cli, *args], cwd=cwd, env=env, capture_output=True, timeout=240)
    assert result.returncode == status, (args, result.returncode, result.stdout, result.stderr)
    return result


def make_project(path, package_link, configured=False):
    test_root = "tests" if configured else "test"
    path.mkdir(parents=True)
    (path / "src").mkdir()
    (path / test_root).mkdir()
    (path / "native").mkdir()
    (path / "native/profile.c").write_text(
        "#include <stdlib.h>\n#include <string.h>\n"
        "int gt_profile_mode(void) {\n#ifdef __OPTIMIZE__\nreturn 1;\n#else\nreturn 0;\n#endif\n}\n"
        "int gt_parent_home_matches(void) { const char *v = getenv(\"GOOSE_HOME\"); "
        f"return v && !strcmp(v, {json.dumps(CALLER_HOME)}); }}\n"
        "int gt_parent_home_empty(void) { const char *v = getenv(\"GOOSE_HOME\"); return !v || !*v; }\n")
    (path / "src/value.goose").write_text("namespace value;\nfn answer() -> i64 { return 42; }\n")
    if configured:
        entry = "goosetest_core.goose"
        generated_import = "goosetest_generated.core.runner"
        (path / "goosetest.json").write_text(json.dumps({
            "version": 1,
            "targets": [{"name": "core", "entry": entry,
                         "tests": [{"path": test_root, "kind": "unit"}]}],
        }))
    else:
        entry = "goosetest_root.goose"
        generated_import = "goosetest_generated.runner"
    root = (f'import goosetest from "{package_link}";\nimport {generated_import};\n'
            'fn main() { exit(goosetest_generated::run_all()); }\n')
    (path / entry).write_text(root)
    (path / (entry.removesuffix(".goose") + ".build")).write_text(
        'c_sources = ["native/profile.c"];\n')
    return entry, test_root


def write_case(project, test_root, expected_mode, empty_home=False):
    home_assertion = "t.assert_true(gt_parent_home_empty());" if empty_home else \
        "t.assert_true(gt_parent_home_matches());"
    (project / test_root / "value_test.goose").write_text(
        "namespace value_test;\nimport goosetest;\nimport src.value;\n"
        'extern "gt_profile_mode" fn profile_mode() -> i64;\n'
        'extern "gt_parent_home_matches" fn gt_parent_home_matches() -> bool;\n'
        'extern "gt_parent_home_empty" fn gt_parent_home_empty() -> bool;\n'
        "fn test_profile(t: goosetest::Test&) {\n"
        f"    t.assert_eq({expected_mode}, profile_mode());\n"
        f"    {home_assertion}\n"
        "    t.assert_eq(42, value::answer());\n}\n")


def compiler_record(log, label):
    value = json.loads(log.read_text())
    assert value["argv"] == label, value
    assert value["home"] is not None, value
    return value


with tempfile.TemporaryDirectory(prefix="goosetest-profile-") as temporary:
    work = Path(temporary).resolve()
    (work / "package").symlink_to(repo, target_is_directory=True)
    project = work / "consumer space ;$(literal)"
    entry, test_root = make_project(project, "../package")
    log = work / "compiler.json"
    compiler = project / "goose-profile-proxy"
    compiler.write_text(
        f"#!{sys.executable}\nimport json, os, sys\nlog = {str(log)!r}\n"
        "open(log, 'w').write(json.dumps({'argv': sys.argv[1:], "
        "'home': os.environ.get('GOOSE_HOME'), 'path': os.environ.get('PATH')}))\n"
        f"os.execv({real_goose!r}, [{real_goose!r}, *sys.argv[1:]])\n")
    compiler.chmod(0o700)
    env = dict(os.environ, GOOSE_HOME=CALLER_HOME)
    absolute_cache = work / "explicit cache ;$(literal)"
    output = "./goosetest_generated/tests"
    write_case(project, test_root, 0)

    # Read-only discovery does not create the default compiler cache.
    run(["list", "--project", str(project)], work, env)
    assert not (project / "goosetest_generated/cache").exists()
    run(["check-mirror", "--project", str(project)], work, env)
    assert not (project / "goosetest_generated/cache").exists()

    # The same sidecar source compiles under both profiles in distinct GOOSE_HOME trees.
    for profile, mode in (("debug", 0), ("optimized", 1)):
        write_case(project, test_root, mode)
        argv = ["build", entry, "-O0", "--debug", "--offline", "-o", output] if profile == "debug" else \
            ["build", entry, "-O2", "--offline", "-o", output]
        run(["test", "--project", str(project), "--profile", profile, "--offline",
             "--cache-root", str(absolute_cache), "--compiler", str(compiler)], work, env)
        record = compiler_record(log, argv)
        assert record["home"] == str(absolute_cache / "default" / profile), record
        assert record["path"] == env["PATH"], record
        assert (absolute_cache / "default" / profile).is_dir()

    # The default cache lives under the generated root but outside its source manifest.
    write_case(project, test_root, 0)
    run(["test", "--project", str(project), "--compiler", str(compiler)], work, env)
    default_cache = project / "goosetest_generated/cache/default/debug"
    record = compiler_record(log, ["build", entry, "-O0", "--debug", "-o", output])
    assert record["home"] == "./goosetest_generated/cache/default/debug", record
    assert default_cache.is_dir()
    run(["list", "--project", str(project)], work, env)
    assert default_cache.is_dir()
    debug_cache = default_cache
    (debug_cache / "owned-by-compiler-cache").write_text("keep")
    write_case(project, test_root, 0)
    run(["test", "--project", str(project), "--compiler", str(compiler)], work, env)
    record = compiler_record(log, ["build", entry, "-O0", "--debug", "-o", output])
    assert record["home"] == "./goosetest_generated/cache/default/debug"
    assert (debug_cache / "owned-by-compiler-cache").read_text() == "keep"

    # Relative roots resolve from the project, and bare compiler names still use PATH.
    relative_root = "relative cache ;$(literal)"
    project_env = dict(env, PATH=str(project) + os.pathsep + env["PATH"])
    write_case(project, test_root, 0)
    run(["test", "--project", str(project), "--cache-root", relative_root,
         "--compiler", compiler.name], work, project_env)
    record = compiler_record(log, ["build", entry, "-O0", "--debug", "-o", output])
    assert record["home"] == "./" + relative_root + "/default/debug", record
    assert record["path"] == project_env["PATH"], record
    assert (project / relative_root / "default" / "debug").is_dir()

    # The launched test executable keeps the caller's absent or empty value.
    for inherited in (None, ""):
        write_case(project, test_root, 0, empty_home=True)
        child_env = dict(env)
        if inherited is None:
            child_env.pop("GOOSE_HOME", None)
        else:
            child_env["GOOSE_HOME"] = inherited
        run(["test", "--project", str(project), "--profile", "debug",
             "--cache-root", str(absolute_cache), "--compiler", str(compiler)], work, child_env)
        record = compiler_record(log, ["build", entry, "-O0", "--debug", "-o", output])
        assert record["home"] == str(absolute_cache / "default" / "debug"), record

    # Configured target key is separate from legacy default, even with the same root/profile.
    configured = work / "configured core"
    core_entry, core_tests = make_project(configured, "../package", configured=True)
    write_case(configured, core_tests, 0)
    configured_cache = work / "shared cache"
    run(["list", "--project", str(configured)], work, env)
    assert not configured_cache.exists()
    disabled = run(["check-mirror", "--project", str(configured)], work, env, 2)
    assert b"disabled" in disabled.stderr
    assert not configured_cache.exists()
    run(["test", "--project", str(configured), "--cache-root", str(configured_cache),
         "--compiler", str(compiler)], work, env)
    core_output = "./goosetest_generated/core/tests"
    record = compiler_record(log, ["build", core_entry, "-O0", "--debug", "-o", core_output])
    assert record["home"] == str(configured_cache / "core" / "debug"), record
    assert (configured_cache / "core" / "debug").is_dir()
    assert not (configured_cache / "default").exists()

    # Cache directories are compiler-owned: source regeneration never prunes them.
    core_sentinel = configured_cache / "core" / "debug" / "must-survive"
    core_sentinel.write_text("keep")
    write_case(configured, core_tests, 0)
    run(["test", "--project", str(configured), "--cache-root", str(configured_cache),
         "--compiler", str(compiler)], work, env)
    assert core_sentinel.read_text() == "keep"

    # Offline compilation failure cannot execute or leave the previous test binary.
    binary = configured / "goosetest_generated/core/tests"
    assert binary.exists()
    (configured / core_entry).write_text(
        'import not_a_real_offline_dependency;\n'
        'import goosetest_generated.core.runner;\n'
        'fn main() { exit(goosetest_generated::run_all()); }\n')
    failed = run(["test", "--project", str(configured), "--offline",
                  "--cache-root", str(configured_cache), "--compiler", str(compiler)], work, env, 2)
    assert b"compilation" in failed.stderr
    assert not binary.exists(), "failed offline compilation left a stale test executable"

print("profile cache partition and child environment tests passed")
