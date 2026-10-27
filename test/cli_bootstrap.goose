// Independent bootstrap for argument and output checks; no native adapter needed.
import goosetest from "..";

import std;

import arguments_test;
import cli_test;
import discovery.selection_test;

fn main() {
    arguments_test::test_valid();
    arguments_test::test_defaults();
    arguments_test::test_invalid();
    arguments_test::test_help_and_limit();
    arguments_test::test_execution_options();
    arguments_test::test_execution_defaults();
    arguments_test::test_execution_invalid();
    arguments_test::test_selection_options();
    arguments_test::test_selection_empty_and_defaults();
    arguments_test::test_selection_invalid();
    selection_test::test_kinds_and_ids();
    selection_test::test_literal_specials_and_empty();
    cli_test::test_output();
    print("cli unit tests passed");
}
