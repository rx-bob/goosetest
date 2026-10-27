// Expected-first byte containment and absolute floating-point comparisons.
namespace goosetest;

import math;
import std;

import src.runtime.context;
import src.runtime.diagnostics_values;
import src.runtime.execution;

fn assert_contains<C>(t: C&, expected_fragment: u8[:], actual_text: u8[:], message: u8[:] = "") {
    t.assertions += 1;
    if find(actual_text, expected_fragment) < 0 {
        record_contains(t, expected_fragment, actual_text, message);
        return from goosetest::run_case;
    }
}

fn valid_tolerance(tolerance: f64) -> bool {
    return tolerance >= 0.0 && !is_inf(tolerance);
}

fn near(expected: f64, actual: f64, tolerance: f64) -> bool {
    if !valid_tolerance(tolerance) || is_nan(expected) || is_nan(actual) {
        return false;
    }
    if expected == actual {
        return true;
    }
    if is_inf(expected) || is_inf(actual) {
        return false;
    }
    return abs(expected - actual) <= tolerance;
}

fn assert_near<C>(t: C&, expected: f64, actual: f64, absolute_tolerance: f64, message: u8[:] = "") {
    t.assertions += 1;
    if !near(expected, actual, absolute_tolerance) {
        record_near(t, expected, actual, absolute_tolerance, message);
        return from goosetest::run_case;
    }
}
