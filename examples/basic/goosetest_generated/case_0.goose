// Generated direct case wrapper; edit the original test source.
namespace goosetest_generated_case_0;

import goosetest;

import integration.arithmetic_test;

fn run(t: goosetest::Test&) {
    if t.results.incomplete {
        return;
    }
    let path = source_path();
    let namespace_name = source_namespace();
    let function_name = source_function();
    let display_name = source_display();
    let identity = goosetest::CaseIdentity {
        test_path: path,
        namespace_name: namespace_name,
        function_name: function_name,
        display_name: display_name,
        declaration_line: 21,
    };
    if t.results.fail_fast_stop {
        goosetest::not_run_case(t.results, identity, "fail-fast");
        return;
    }
    goosetest::execute_fixture(t, identity) {
        var fixture = arithmetic_test::Fixture {
            ..
        };
        goosetest::run_phase(t, goosetest::Phase.Setup) {
            arithmetic_test::before_each(t, fixture);
        }
        if t.failures == 0 && !t.results.incomplete {
            goosetest::run_phase(t, goosetest::Phase.Body) {
                arithmetic_test::test_round_trip(t, fixture);
            }
        }
        goosetest::run_phase(t, goosetest::Phase.Cleanup) {
            arithmetic_test::after_each(t, fixture);
        }
    }
}

fn source_path() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("integration/arithmetic_test.goose");
    return text;
}

fn source_namespace() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("arithmetic_test");
    return text;
}

fn source_function() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("test_round_trip");
    return text;
}

fn source_display() -> u8[>..] {
    var text: u8[>..] = [];
    return text;
}
