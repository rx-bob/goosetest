// Independent stage-result oracle does not execute generated consumer tests.
import goosetest from "..";

import std;

import execution.command_test;

fn main() {
    command_test::test_normal_status();
    command_test::test_incomplete_outcomes();
    command_test::test_cleanup_errors();
    command_test::test_cancellation();
    print("execution unit tests passed");
}
