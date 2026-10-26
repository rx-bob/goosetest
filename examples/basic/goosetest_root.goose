// Consumer root owns package declarations and propagates the real process status.
import goosetest from "../..";

import test_support.bootstrap;

fn main() {
    exit(basic_bootstrap::run());
}
