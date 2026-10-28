// Lexical validation rejects traversal while accepting import-safe relative roots.
namespace config_validation_test;

import goosetest;
import src.config.validation;

fn test_target_names_and_paths(outer: goosetest::Test&) {
    assert(config::valid_target_name("core_2"));
    assert(!config::valid_target_name("Core"));
    assert(!config::valid_target_name("cache"));
    assert(config::valid_path("goosetest_core.goose", true, false));
    assert(config::valid_path("tests/request", false, false));
    assert(!config::valid_path("tests/../request", false, false));
    assert(!config::valid_path("/tests/request", false, false));
}
