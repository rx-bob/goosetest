// Independent verifier owns disposable builds and checks the self-host runner from outside.

import goosetest from "..";

import os;

import goosetest.src.platform.process;

fn main() {
    let result = process::run(["python3", "integration/fixtures/verify.py"], ".", process::Limits {
            deadline_ms: 3600000,
            grace_ms: 1000
        });
    if result.outcome != process::Outcome.Exited || result.cleanup_error != 0 {
        exit(2);
    }
    exit(result.exit_code as i32);
}
