// Generated direct case wrapper; edit the original test source.
namespace goosetest_generated_case_2;

import goosetest;

import test.calculator_test;

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
        declaration_line: 16,
    };
    if t.results.fail_fast_stop {
        goosetest::not_run_case(t.results, identity, "fail-fast");
        return;
    }
    goosetest::execute_case(t, identity) {
        calculator_test::test_zero_identity(t);
    }
}

fn source_path() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("test/calculator_test.goose");
    return text;
}

fn source_namespace() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("calculator_test");
    return text;
}

fn source_function() -> u8[>..] {
    var text: u8[>..] = [];
    text.append("test_zero_identity");
    return text;
}

fn source_display() -> u8[>..] {
    var text: u8[>..] = [];
    return text;
}
