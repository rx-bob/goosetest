// Materialize current generated consumers before checking all shipping Goose files.

import goosetest from "..";

import os;
import std;

import goosetest.src.platform.process;
import style_check;

fn main() {
    for project in[".", "examples/basic"] {
        let result = process::run(["build/goosetest", "test", "--project", project], ".",
            process::Limits {
                deadline_ms: 180000,
                grace_ms: 1000
            });
        if result.outcome != process::Outcome.Exited || result.cleanup_error != 0 {
            write_stderr("Representative generation did not complete.\n");
            exit(2);
        }
        if result.exit_code != 0 {
            exit(result.exit_code as i32);
        }
    }
    let configured = process::run(["python3", "-B", "integration/fixtures/configured/verify.py",
        "build/goosetest"], ".", process::Limits {
            deadline_ms: 180000,
            grace_ms: 1000
        });
    if configured.outcome != process::Outcome.Exited || configured.cleanup_error != 0 {
        write_stderr("Configured target generation did not complete.\n");
        exit(2);
    }
    if configured.exit_code != 0 {
        write_stderr(str("Configured target verifier failed: ", configured.exit_code, "\n"));
        exit(configured.exit_code as i32);
    }
    var checked: i64 = 0;
    var valid = style_check::root_sources(checked);
    for directory in["src", "test", "integration", "test_support", "examples", "scripts", "goosetest_generated"] {
        if !style_check::directory(directory, true, 0, checked) {
            valid = false;
        }
    }
    if !valid || checked == 0 {
        write_stderr("Shipping source checks failed or no files were checked.\n");
        exit(2);
    }
    write_stdout(str("Style checked ", checked, " Goose files, including generated consumers.\n"));
}
