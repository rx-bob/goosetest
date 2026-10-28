// Sequential build/run policy holds exclusive artifact ownership through child cleanup.
namespace command;

import os;
import std;

import src.arguments;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.selection;
import src.execution.build;
import src.generation.artifacts;
import src.generation.model;
import src.generation.runner;
import src.platform.process;
import src.platform.staging;

struct Target {
    name: const u8[:],
    entry: const u8[:],
}

struct Result {
    status: i32,
    continue_allowed: bool,
}

fn run_locked(options: arguments::Options&, manifest: discovery::Manifest&, audit: discovery::MirrorAudit&,
    target: Target, fd: i32) -> Result {
    var modules: generation::Module[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var errors: u8[>..] = [];
    var output = generation::new_output(modules, paths, sources, errors);
    generation::generate(output, manifest, audit,
        selection::Options {
            filter: options.filter,
            suite: options.suite
        }, options.fail_fast);
    if generation::status(output) != 0 {
        write_stderr(str("ERROR: generation: ", output.error, "\nRun incomplete; no tests executed.\n"));
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    return materialize(options, output, fd, target);
}

fn materialize(options: arguments::Options&, output: generation::Output&, fd: i32, target: Target) -> Result {
    let published = artifacts::publish(fd, output, target.name);
    if published != 0 {
        write_stderr(str("ERROR: artifact publication for target ", target_label(target), ": ",
            published, "\nRun incomplete.\n"));
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    let binary_path: u8[>..] = if target.name.len == 0 {
        "tests"
    } else {
        str(target.name, "/tests")
    };
    let completion_path: u8[>..] = if target.name.len == 0 {
        "completion"
    } else {
        str(target.name, "/completion")
    };
    let reset = staging::reset(fd, binary_path, completion_path);
    if reset != 0 {
        write_stderr(str("ERROR: stale execution artifact removal for target ", target_label(target), ": ",
            reset, "\nRun incomplete.\n"));
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    let cache_key: const u8[:] = if target.name.len == 0 {
        "default"
    } else {
        target.name
    };
    var compiler_home: u8[>..] = [];
    if !build::cache_home(compiler_home, options.cache_root, cache_key, options.profile) {
        write_stderr("ERROR: compiler cache path exceeds 4095 bytes; run incomplete.\n");
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    let cache_ready = staging::cache_prepare(options.project, compiler_home);
    if cache_ready != 0 {
        write_stderr(str("ERROR: compiler cache directory creation: ", -cache_ready,
            " for target ", target_label(target), "; check --cache-root and directory permissions. ",
            "Run incomplete.\n"));
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    return build_and_execute(options, target, compiler_home, binary_path, completion_path, fd);
}

fn build_and_execute(options: arguments::Options&, target: Target, compiler_home: const u8[:],
    binary_path: const u8[:], completion_path: const u8[:], fd: i32) -> Result {
    let output_path = str("./goosetest_generated/", binary_path);
    var argv: const u8[:][>..] = [];
    build::append_arguments(argv, options.compiler, target.entry, output_path, options.profile, options.offline);
    let built = process::run_with_goose_home(argv, options.project, compiler_home,
        process::Limits {
            deadline_ms: options.compile_timeout_seconds * 1000,
            ..
        });
    let status = stage_status(built, false);
    if status != 0 {
        diagnose("compilation", target, built);
        return Result {
            status: status,
            continue_allowed: process_clean(built),
        };
    }
    let execute_path = str("./goosetest_generated/", binary_path);
    let execute: const u8[:][2] = [execute_path, "--goosetest-completion"];
    let ran = process::run(execute, options.project,
        process::Limits {
            deadline_ms: options.run_timeout_seconds * 1000,
            ..
        });
    let result = stage_status(ran, true);
    if result != 0 && result != 1 {
        diagnose("execution", target, ran);
        return Result {
            status: result,
            continue_allowed: process_clean(ran),
        };
    }
    return record_completion(fd, completion_path, target, result);
}

fn record_completion(fd: i32, completion_path: const u8[:], target: Target, result: i32) -> Result {
    if staging::completion_at(fd, completion_path, result) != 0 {
        write_stderr(str("ERROR: execution for target ", target_label(target),
            " ended without matching completion record; run incomplete.\n"));
        return Result {
            status: 2,
            continue_allowed: true,
        };
    }
    return Result {
        status: result,
        continue_allowed: true,
    };
}

fn process_clean(result: process::ProcessResult) -> bool {
    return result.outcome != process::Outcome.Cancelled && result.cleanup_error == 0 &&
    (result.pid <= 0 || result.reaped);
}

fn stage_status(result: process::ProcessResult, execution: bool) -> i32 {
    if result.outcome == process::Outcome.Cancelled {
        return (128 + result.signal)as i32;
    }
    if result.cleanup_error != 0 || (result.pid > 0 && !result.reaped) {
        return 2;
    }
    if result.outcome != process::Outcome.Exited {
        return 2;
    }
    if result.exit_code == 0 || (execution && result.exit_code == 1) {
        return result.exit_code as i32;
    }
    return 2;
}

fn target_label(target: Target) -> const u8[:] {
    if target.name.len == 0 {
        return "default";
    }
    return target.name;
}

fn diagnose(stage: const u8[:], target: Target, result: process::ProcessResult) {
    if result.outcome == process::Outcome.Deadline {
        write_stderr(str("ERROR: ", stage, " for target ", target_label(target),
            " exceeded its deadline; run incomplete.\n"));
    } else {
        write_stderr(str("ERROR: ", stage, " for target ", target_label(target), " failed; exit=",
            result.exit_code, " signal=", result.signal, " native_error=", result.native_error,
            " cleanup_error=", result.cleanup_error, "; run incomplete.\n"));
    }
}
