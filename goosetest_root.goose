// Run the framework through the same generated entry point as consumer projects.

import os;

import goosetest;
import goosetest_generated.runner;
import test_support.selfhost;

fn main() {
    if !selfhost_support::prepare() {
        selfhost_support::cleanup();
        exit(2);
    }
    let status = goosetest_generated::run_all();
    if !selfhost_support::cleanup() {
        exit(2);
    }
    exit(status);
}
