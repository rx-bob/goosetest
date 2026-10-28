// Ordering compares byte prefixes and stable identities independently of insertion order.
namespace ordering_test;

import std;

import goosetest;
import src.reporting.console;
import src.reporting.ordering;
import test_support.runtime;

fn test_byte_prefixes(outer: goosetest::Test&) {
    assert(reporting::compare_bytes("", "") == 0);
    assert(reporting::compare_bytes("a", "aa") < 0);
    assert(reporting::compare_bytes("aa", "a") > 0);
    assert(reporting::compare_bytes("a\0b", "a\0c") < 0);
    assert(reporting::compare_bytes("\xFF", "\x7F") > 0);
}

fn test_declaration_before_function(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
                test_path: "test/a_test.goose",
                namespace_name: "same",
                function_name: "test_a",
                declaration_line: 20,
                ..
            }, "later");
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
                test_path: "test/a_test.goose",
                namespace_name: "same",
                function_name: "test_z",
                declaration_line: 10,
                ..
            }, "earlier");
        assert(reporting::case_less(t.results, 1, 0));
        assert( !reporting::case_less(t.results, 0, 1));
        assert( !reporting::case_less(t.results, 0, 0));
        assert(t.results.cases[0].identity.declaration_line == 20);
    }
}

fn test_duplicate_reason_tiebreak(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
            }, "z");
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
            }, "a");
        assert(reporting::case_less(t.results, 1, 0));
        assert( !reporting::case_less(t.results, 0, 1));
    }
}

fn test_suite_hook_identity_order(outer: goosetest::Test&) {
    let forward = render_hooks(false);
    let backward = render_hooks(true);
    outer.assert_eq(forward, backward, "hook collection order must not change the report");
    let first = find(forward[..], "::a_hook");
    let last = find(forward[..], "::z_hook");
    outer.assert_true(first >= 0 && last > first, "hook function names break equal-location ties");
}

fn render_hooks(reverse: bool) -> u8[>..] {
    var text: u8[>..] = [];
    runtime_support::with_test() {
        t =>
        const names: const u8[:][2] = ["a_hook", "z_hook"];
        for index in 0..2 {
            let name = names[if reverse {
                    1 - index
                } else {
                    index
                }];
            goosetest::run_suite_hook(t, goosetest::CaseIdentity {
                    test_path: "integration/same_test.goose",
                    namespace_name: "same",
                    function_name: name,
                    declaration_line: 10,
                    ..
                }, goosetest::Phase.SuiteSetup) {
                t.fail("same");
            }
        }
        reporting::render(t.results) {
            chunk => text.append(chunk);
        }
    }
    return text;
}
