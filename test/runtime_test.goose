// Bootstrap unit-test entry point; no dependency on goosetest's own verdicts.
import goosetest from "..";

import runtime.assertions_test;
import runtime.context_test;
import runtime.execution_test;

fn main() {
    context_test::test_reset();
    execution_test::test_hard_stop();
    execution_test::test_soft_failures();
    execution_test::test_soft_then_hard();
    assertions_test::test_passing_values();
    assertions_test::test_boolean_failures();
    assertions_test::test_explicit_and_unequal_failures();
    assertions_test::test_failed_text_and_slices();
    assertions_test::test_format_hooks();
    assertions_test::test_empty_and_different_length_slices();
}
