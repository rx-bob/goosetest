// Compiler v2026.3 supports -o only; no long --output spelling exists.

import goosetest from "..";

import os;

import goosetest.src.platform.process;

fn main() {
    if !make_dir("build") {
        write_stderr("Cannot create build directory.\n");
        exit(2);
    }
    let result = process::run(["goose", "build", "--debug", "main.goose", "-o", "build/goosetest"], ".",
        process::Limits {
            deadline_ms: 120000,
            grace_ms: 1000
        });
    if result.outcome != process::Outcome.Exited || result.cleanup_error != 0 {
        write_stderr("CLI build did not complete.\n");
        exit(2);
    }
    exit(result.exit_code as i32);
}
