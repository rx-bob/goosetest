// Sequential build/run policy holds exclusive artifact ownership through child cleanup.
namespace command;

import os;
import std;

import src.arguments;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.selection;
import src.generation.artifacts;
import src.generation.model;
import src.generation.runner;
import src.platform.filesystem;
import src.platform.process;
import src.platform.staging;

fn run(options: arguments::Options&, manifest: discovery::Manifest&, audit: discovery::MirrorAudit&) -> i32 {
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
        return 2;
    }
    let fd = staging::create(options.project);
    if fd < 0 {
        write_stderr(str("ERROR: artifacts: native error ", - fd,
            "; require regular goosetest_root.goose and writable, owned goosetest_generated/.\n",
            "A concurrent invocation must release ownership before retrying. Run incomplete.\n"));
        return 2;
    }
    let result = materialize(options, output, fd);
    let closed = filesystem::close_project(fd);
    if closed != 0 {
        write_stderr(str("ERROR: artifact close: ", closed, "\nRun incomplete.\n"));
        return 2;
    }
    return result;
}

fn materialize(options: arguments::Options&, output: generation::Output&, fd: i32) -> i32 {
    let published = artifacts::publish(fd, output);
    if published != 0 {
        write_stderr(str("ERROR: artifact publication: ", published, "\nRun incomplete.\n"));
        return 2;
    }
    let reset = staging::reset(fd);
    if reset != 0 {
        write_stderr(str("ERROR: stale execution artifact removal: ", reset, "\nRun incomplete.\n"));
        return 2;
    }
    let argv: const u8[:][6] = [options.compiler, "build", "--debug", "goosetest_root.goose", "-o",
        "./goosetest_generated/tests"];
    let built = process::run(argv, options.project,
        process::Limits {
            deadline_ms: options.compile_timeout_seconds * 1000,
            ..
        });
    let status = stage_status(built, false);
    if status != 0 {
        diagnose("compilation", built);
        return status;
    }
    let execute: const u8[:][2] = ["./goosetest_generated/tests", "--goosetest-completion"];
    let ran = process::run(execute, options.project,
        process::Limits {
            deadline_ms: options.run_timeout_seconds * 1000,
            ..
        });
    let result = stage_status(ran, true);
    if result != 0 && result != 1 {
        diagnose("execution", ran);
        return result;
    }
    if staging::completion(fd, result) != 0 {
        write_stderr("ERROR: execution ended without matching completion record; run incomplete.\n");
        return 2;
    }
    return result;
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

fn diagnose(stage: const u8[:], result: process::ProcessResult) {
    if result.outcome == process::Outcome.Deadline {
        write_stderr(str("ERROR: ", stage, " exceeded its deadline; run incomplete.\n"));
    } else {
        write_stderr(str("ERROR: ", stage, " failed; exit=", result.exit_code, " signal=", result.signal,
            " native_error=", result.native_error, " cleanup_error=", result.cleanup_error,
            "; run incomplete.\n"));
    }
}
