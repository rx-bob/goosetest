// Install the CLI separately from the source package used by consumer test roots.

import goosetest from "..";

import os;
import std;

import goosetest.src.platform.process;

fn main() {
    var prefix: u8[>..] = [];
    if !env("GOOSETEST_INSTALL_PREFIX", prefix) {
        if !env("HOME", prefix) || prefix.len == 0 {
            write_stderr("HOME is unset; set GOOSETEST_INSTALL_PREFIX to an installation directory.\n");
            exit(2);
        }
        prefix.append("/.local");
    }
    if prefix.len == 0 {
        write_stderr("GOOSETEST_INSTALL_PREFIX must not be empty.\n");
        exit(2);
    }
    let directory = str(prefix, "/bin");
    let created = process::run(["install", "-d", directory], ".");
    if created.outcome != process::Outcome.Exited || created.exit_code != 0 || created.cleanup_error != 0 {
        write_stderr("Cannot create installation directory.\n");
        exit(2);
    }
    let destination = str(directory, "/goosetest");
    let copied = process::run(["install", "-m", "755", "build/goosetest", destination], ".");
    if copied.outcome != process::Outcome.Exited || copied.exit_code != 0 || copied.cleanup_error != 0 {
        write_stderr("CLI installation failed.\n");
        exit(2);
    }
    write_stdout(str("Installed ", destination, "\nAdd ", directory, " to PATH if needed.\n"));
}
