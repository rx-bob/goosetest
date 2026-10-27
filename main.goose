// Process entry preserves CLI status; discovery never compiles or runs project code.
import os;

import src.arguments;
import src.cli;

fn main() {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    for index in 1..arg_count() {
        var value: u8[>..] = [];
        arg(index, value);
        arguments::consume(options, value);
    }
    arguments::finish(options);
    exit(cli::run(options));
}
