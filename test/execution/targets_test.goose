// Coordinator rules preserve completed failures, cancellation, and untouched targets.
namespace targets_test;

import goosetest;
import src.execution.targets;

fn test_aggregate_precedence(outer: goosetest::Test&) {
    var results: targets::Result[3] = [
        targets::from_execution(1, 1, true),
        targets::from_execution(2, 1, true),
        targets::from_execution(0, 1, true)
    ];
    assert(targets::aggregate(results) == 2);
    results[1] = targets::from_execution(0, 1, true);
    assert(targets::aggregate(results) == 1);
    results[0] = targets::from_execution(0, 1, true);
    assert(targets::aggregate(results) == 0);
    results[2] = targets::from_execution(143, 1, false);
    assert(targets::aggregate(results) == 143);
}

fn test_continuation_policy(outer: goosetest::Test&) {
    let assertion = targets::from_execution(1, 1, true);
    let compiler_failure = targets::from_execution(2, 1, true);
    let cleanup_failure = targets::from_execution(2, 1, false);
    let cancelled = targets::from_execution(130, 1, false);
    assert(targets::should_continue(assertion, false));
    assert(!targets::should_continue(assertion, true));
    assert(targets::should_continue(compiler_failure, false));
    assert(!targets::should_continue(compiler_failure, true));
    assert(!targets::should_continue(cleanup_failure, false));
    assert(!targets::should_continue(cancelled, false));
}

fn test_skipped_excluded_and_not_run_states(outer: goosetest::Test&) {
    let disabled = targets::from_execution(0, 0, true);
    let excluded = targets::selection_excluded();
    let untouched = targets::not_run();
    assert(disabled.state == targets::State.DisabledOnly);
    assert(excluded.state == targets::State.SelectionExcluded);
    assert(untouched.state == targets::State.NotRun);
    assert(targets::aggregate([disabled, excluded, untouched]) == 0);
}
