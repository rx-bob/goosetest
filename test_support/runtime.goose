// Bootstrap helper owns all result storage until the test callback finishes reporting.
namespace runtime_support;

import goosetest;

fn with_test<F>(limits: goosetest::Limits = goosetest::Limits {
    }) {
    var cases: goosetest::CaseResult[>..] = [];
    var failures: goosetest::Failure[>..] = [];
    var diagnostics: u8[>..] = [];
    var metadata: u8[>..] = [];
    var results = goosetest::new_results(cases, failures, diagnostics, metadata, limits);
    var t = goosetest::Test {
        results: results,
        ..
    };
    F(t);
}
