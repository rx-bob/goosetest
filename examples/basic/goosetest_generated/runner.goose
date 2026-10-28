// Generated entry behind the authored package root.
namespace goosetest_generated;

import goosetest;
import goosetest_generated.completion;
import goosetest_generated.dispatch_0_0;
import goosetest_generated.report;

fn run_all() -> i32 {
    var cases: goosetest::CaseResult[>..] = [];
    var failures: goosetest::Failure[>..] = [];
    var diagnostics: u8[>..] = [];
    var metadata: u8[>..] = [];
    let limits = goosetest::Limits {
        cases: 4,
        metadata_bytes: 233,
        ..
    };
    var results = goosetest::new_results(cases, failures, diagnostics, metadata, limits);
    var t = goosetest::Test {
        results: results,
        ..
    };
    goosetest_generated_dispatch_0_0::run(t);
    goosetest_generated_report::report(results, 4);
    return goosetest_generated_completion::finish(goosetest::run_status(results), "goosetest_generated/completion");
}
