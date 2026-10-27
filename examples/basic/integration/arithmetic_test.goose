// Integration suites need no source mirror and can own fresh per-case fixtures.
namespace arithmetic_test;

import goosetest;
import src.calculator;

struct Fixture {
    initial: i64 = 40,
    current: i64 = 0
}

fn before_each(t: goosetest::Test&, fixture: Fixture&) {
    fixture.current = fixture.initial;
    t.assert_eq(40, fixture.current, "fresh fixture starts at forty");
}

fn after_each(t: goosetest::Test&, fixture: Fixture&) {
    t.assert_eq(fixture.initial, fixture.current, "round trip restores the starting value");
}

fn test_round_trip(t: goosetest::Test&, fixture: Fixture&) {
    fixture.current = calculator::add(fixture.current, 2);
    t.assert_eq(42, fixture.current);
    fixture.current = calculator::subtract(fixture.current, 2);
    t.assert_eq(40, fixture.current);
}
