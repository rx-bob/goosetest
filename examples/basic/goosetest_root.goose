// Authored package root stays stable while discovery refreshes generated orchestration.

import goosetest from "../..";

import goosetest_generated.runner;

fn main() {
    exit(goosetest_generated::run_all());
}
