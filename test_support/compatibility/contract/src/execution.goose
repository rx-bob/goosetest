// Generic recovery boundary; imports resolve from the fixture package root.
namespace goosetest;

import goosetest;
import.marker;

fn run_case<F>(t: Test&) {
    marker::check_loaded();
    F();
}
