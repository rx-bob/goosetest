// Independent byte-level and chunk-boundary checks for terminal-safe report text.
namespace formatting_test;

import goosetest.src.reporting.formatting;
import goosetest.src.runtime.results;

fn test_labels() {
    assert(reporting::outcome_label(goosetest::Outcome.Passed) == "PASS");
    assert(reporting::outcome_label(goosetest::Outcome.Failed) == "FAIL");
    assert(reporting::outcome_label(goosetest::Outcome.Skipped) == "SKIP");
    assert(reporting::outcome_label(goosetest::Outcome.RunnerError) == "ERROR");
    assert(reporting::phase_label(goosetest::Phase.Setup) == "setup");
    assert(reporting::phase_label(goosetest::Phase.Body) == "test");
    assert(reporting::phase_label(goosetest::Phase.Cleanup) == "cleanup");
    assert(reporting::phase_label(goosetest::Phase.SuiteSetup) == "suite setup");
    assert(reporting::phase_label(goosetest::Phase.SuiteCleanup) == "suite cleanup");
}

fn test_escaping() {
    let source = "a\\\n\r\t\0\x1B[31m\x7F\x85é";
    let expected = "a\\\\\\x0A\\x0D\\x09\\x00\\x1B[31m\\x7F\\x85\\xC3\\xA9";
    var appended: u8[>..] = [];
    reporting::append_escaped(appended, source);
    assert(appended == expected);
    var streamed: u8[>..] = [];
    reporting::escape(source) {
        part => streamed.append(part);
    }
    assert(streamed == expected);
    var empty_calls: i64 = 0;
    reporting::escape("") {
        part => empty_calls += 1;
    }
    assert(empty_calls == 0);
}

fn test_chunk_bound() {
    var source: u8[>..] = [];
    for index in 0..5000 {
        source.push(0);
    }
    var total: i64 = 0;
    var calls: i64 = 0;
    reporting::escape(source) {
        part =>
        assert(part.len > 0 && part.len <= 4096);
        assert(part.len % 4 == 0);
        for index in 0..part.len / 4 {
            assert(part[index * 4..index * 4 + 4] == "\\x00");
        }
        total += part.len;
        calls += 1;
    }
    assert(total == 20000 && calls == 5);
}
