// Only the directory bootstrap needs no native process sidecar.

import os;

fn main() {
    if !make_dir("build") {
        write_stderr("Cannot create build directory.\n");
        exit(2);
    }
}
