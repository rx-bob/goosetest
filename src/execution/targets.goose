// Target result precedence and continuation policy are independent of CLI output.
namespace targets;

enum State {
    NotRun,
    SelectionExcluded,
    DisabledOnly,
    Passed,
    AssertionFailure,
    Incomplete,
    Cancelled,
}

struct Result {
    state: State = State.NotRun,
    status: i32 = 0,
    continue_allowed: bool = true,
}

fn not_run() -> Result {
    return Result {
    };
}

fn selection_excluded() -> Result {
    return Result {
        state: State.SelectionExcluded,
        ..
    };
}

fn from_execution(status: i32, executable_cases: i64, continue_allowed: bool) -> Result {
    if status >= 128 {
        return Result {
            state: State.Cancelled,
            status: status,
            continue_allowed: false,
        };
    }
    if status == 2 {
        return Result {
            state: State.Incomplete,
            status: status,
            continue_allowed: continue_allowed,
        };
    }
    if status == 1 {
        return Result {
            state: State.AssertionFailure,
            status: status,
            continue_allowed: continue_allowed,
        };
    }
    if executable_cases == 0 {
        return Result {
            state: State.DisabledOnly,
            ..
        };
    }
    return Result {
        state: State.Passed,
        ..
    };
}

fn should_continue(result: Result, fail_fast: bool) -> bool {
    if result.state == State.Cancelled || (result.status == 2 && !result.continue_allowed) {
        return false;
    }
    return !fail_fast || result.status == 0;
}

fn aggregate(results: Result[:]) -> i32 {
    for result in results {
        if result.state == State.Cancelled {
            return result.status;
        }
    }
    for result in results {
        if result.status == 2 {
            return 2;
        }
    }
    for result in results {
        if result.status == 1 {
            return 1;
        }
    }
    return 0;
}
