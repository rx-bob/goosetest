// ASCII-safe plain-text formatting; streamed escaping keeps scratch bounded.
namespace reporting;

import src.runtime.results;

fn outcome_label(outcome: goosetest::Outcome) -> const u8[:] {
    match outcome {
        Passed => {
            return "PASS";
        },
        Failed => {
            return "FAIL";
        },
        Skipped => {
            return "SKIP";
        },
        NotRun => {
            return "NOT RUN";
        },
        RunnerError => {
            return "ERROR";
        },
    }
}

fn phase_label(phase: goosetest::Phase) -> const u8[:] {
    match phase {
        Setup => {
            return "setup";
        },
        Body => {
            return "test";
        },
        Cleanup => {
            return "cleanup";
        },
        SuiteSetup => {
            return "suite setup";
        },
        SuiteCleanup => {
            return "suite cleanup";
        },
    }
}

fn append_escaped(out: u8[>..]&, value: u8[:]) {
    for byte in value {
        append_byte(out, byte);
    }
}

fn escape<F>(value: u8[:]) {
    var out: u8[>..] = [];
    for byte in value {
        if out.len > 4092 {
            F(out[..]);
            out.clear();
        }
        append_byte(out, byte);
    }
    if out.len > 0 {
        F(out[..]);
    }
}

fn append_byte(out: u8[>..]&, byte: u8) {
    if byte == '\\' {
        out.append("\\\\");
    } else if byte < 32 || byte >= 127 {
        let hex = "0123456789ABCDEF";
        out.append("\\x");
        out.push(hex[(byte / 16)as i64]);
        out.push(hex[(byte % 16)as i64]);
    } else {
        out.push(byte);
    }
}
