// Ordinary named tests are discovered automatically from this mirrored suite.
namespace calculator_test;

import goosetest;
import src.calculator;

fn test_addition(t: goosetest::Test&) {
    t.assert_eq(42, calculator::add(20, 22));
}

fn test_subtraction(t: goosetest::Test&) {
    t.assert_eq(38, calculator::subtract(40, 2));
}

fn test_zero_identity(t: goosetest::Test&) {
    t.assert_eq(7, calculator::add(7, 0));
    t.assert_eq(-7, calculator::add(-7, 0));
}
