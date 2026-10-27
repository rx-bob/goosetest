// Independent bootstrap for argument and output checks; no native adapter needed.
import goosetest from "..";

import std;

import arguments_test;
import cli_test;

fn main() {
    arguments_test::test_valid();
    arguments_test::test_defaults();
    arguments_test::test_invalid();
    arguments_test::test_help_and_limit();
    cli_test::test_output();
    print("cli unit tests passed");
}
