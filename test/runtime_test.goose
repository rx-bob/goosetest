// Bootstrap unit-test entry point; no dependency on goosetest's own verdicts.
import goosetest from "..";

import runtime.assertions_test;
import runtime.assertions_values_test;
import runtime.context_test;
import runtime.diagnostics_test;
import runtime.execution_test;
import runtime.metadata_test;
import runtime.results_test;
import runtime.value_format_test;

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
    assertions_values_test::test_contains_values();
    assertions_values_test::test_contains_failure();
    assertions_values_test::test_near_values();
    assertions_values_test::test_near_failures();
    assertions_values_test::test_value_diagnostic_budgets();
    results_test::test_totals();
    results_test::test_case_limit();
    results_test::test_zero_limits();
    results_test::test_skipped_only();
    results_test::test_invalid_limits();
    diagnostics_test::test_failure_limit();
    diagnostics_test::test_byte_limit();
    diagnostics_test::test_byte_boundary();
    diagnostics_test::test_zero_failure_budget();
    diagnostics_test::test_phase_and_lifetime();
    diagnostics_test::test_format_budget();
    diagnostics_test::test_explicit_budget();
    value_format_test::test_large_text();
    value_format_test::test_collection_stops_formatting();
    value_format_test::test_custom_hook_limit();
    value_format_test::test_nested_arrays();
    value_format_test::test_array_storage_and_bytes();
    value_format_test::test_nested_byte_escaping();
    value_format_test::test_scalar_format_hooks();
    metadata_test::test_retained_identity();
    metadata_test::test_metadata_limit();
    metadata_test::test_metadata_atomicity();
}
