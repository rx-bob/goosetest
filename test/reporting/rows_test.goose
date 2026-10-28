// Streaming rows escape identity fields and omit headings for empty sections.
namespace rows_test;

import std;

import goosetest;
import src.reporting.rows;
import test_support.runtime;

fn test_skip_row_escaping(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
                test_path: "test/a\n_test.goose",
                namespace_name: "space",
                function_name: "test_case",
                declaration_line: 7,
                display_name: "label\tname",
                ..
            }, "pending\0reason");
        var text: u8[>..] = [];
        reporting::case_row(t.results, t.results.cases[0]) {
            chunk => text.append(chunk);
        }
        assert(text == str("SKIP test/a\\x0A_test.goose::space::test_case (test/a\\x0A_test.goose:7)\n",
            "  display: label\\x09name\n  reason: pending\\x00reason\n"));
    }
}

fn test_empty_failure_sections(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        let indices: i64[0] = [];
        var text: u8[>..] = [];
        reporting::failure_rows(t.results, indices, false) {
            chunk => text.append(chunk);
        }
        reporting::suite_failure_rows(t.results, indices, false) {
            chunk => text.append(chunk);
        }
        assert(text.len == 0);
        assert(reporting::suite_phase(goosetest::Phase.SuiteSetup));
        assert(reporting::suite_phase(goosetest::Phase.SuiteCleanup));
        assert(!reporting::suite_phase(goosetest::Phase.Setup));
        assert(!reporting::suite_phase(goosetest::Phase.Cleanup));
        assert(!reporting::suite_phase(goosetest::Phase.Body));
    }
}
