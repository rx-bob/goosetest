// Identity and skip metadata survive their input scopes and respect a separate budget.
namespace metadata_test;

import goosetest;
import goosetest.test_support.runtime;

fn test_retained_identity() {
    runtime_support::with_test() {
        t =>
        record_temporary_identity(t);
        goosetest::execute_case(t, goosetest::CaseIdentity {
                function_name: "later",
                ..
            }) {
        }
        let id = t.results.cases[0].identity;
        assert(goosetest::metadata_text(t.results, id.test_path) == "test/local_test.goose");
        assert(goosetest::metadata_text(t.results, id.namespace_name) == "local_test");
        assert(goosetest::metadata_text(t.results, id.function_name) == "test_local");
        assert(goosetest::metadata_text(t.results, id.display_name) == "temporary display");
        assert(id.declaration_line == 42);
        assert(t.results.cases[0].outcome == goosetest::Outcome.Passed);
    }
}

fn record_temporary_identity(t: goosetest::Test&) {
    var path: u8[>..] = [];
    var name: u8[>..] = [];
    var label: u8[>..] = [];
    path.append("test/local_test.goose");
    name.append("test_local");
    label.append("temporary display");
    let identity = goosetest::CaseIdentity {
        test_path: path,
        namespace_name: "local_test",
        function_name: name,
        display_name: label,
        declaration_line: 42,
    };
    goosetest::execute_case(t, identity) {
    }
}

fn test_metadata_limit() {
    runtime_support::with_test(goosetest::Limits {
            metadata_bytes: 3,
            ..
        }) {
        t =>
        goosetest::execute_case(t, goosetest::CaseIdentity {
                function_name: "abc",
                ..
            }) {
        }
        assert(t.results.metadata == "abc");
        assert(goosetest::run_status(t.results) == 0);
        var reached = false;
        goosetest::execute_case(t, goosetest::CaseIdentity {
                test_path: "x",
                ..
            }) {
            reached = true;
        }
        assert( !reached);
        assert(t.results.metadata == "abc");
        assert(t.results.cases.len == 1);
        assert(t.results.totals.passed == 1);
        assert(t.results.terminal == goosetest::TerminalError.MetadataLimit);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_metadata_atomicity() {
    runtime_support::with_test(goosetest::Limits {
            metadata_bytes: 2,
            ..
        }) {
        t =>
        let id = goosetest::CaseIdentity {
            test_path: "a",
            function_name: "b",
            ..
        };
        goosetest::skip_case(t.results, id, "x");
        assert(t.results.metadata.len == 0);
        assert(t.results.cases.len == 0);
        assert(t.results.totals.skipped == 0);
        assert(t.results.terminal == goosetest::TerminalError.MetadataLimit);
        assert(goosetest::terminal_diagnostic(t.results) == "incomplete run: metadata byte limit exhausted");
    }
}
