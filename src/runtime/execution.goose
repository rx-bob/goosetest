// Explicit recovery boundary for direct case calls and assertion bridges.
namespace goosetest;

import src.runtime.context;

fn run_case<F>(t: Test&) {
    reset(t);
    F();
}
