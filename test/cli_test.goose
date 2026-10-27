// CLI dispatch rejects invalid options before help or any project access.
namespace cli_test;

import goosetest;
import src.arguments;
import src.cli;

fn test_invalid_options_before_help(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    options.help = true;
    options.error = "unit test invalid options";
    assert(cli::run(options) == 2);
    assert(project.len == 0);
}

fn test_help_without_project(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    options.help = true;
    assert(cli::run(options) == 0);
    assert(project.len == 0);
}
