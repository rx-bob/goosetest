// Config tests use disposable project files and prove parsing performs no writes.
namespace config_load_test;

import os;
import std;

import goosetest;
import src.arguments;
import src.cli;
import src.config.load;
import src.config.model;
import test_support.filesystem;
import test_support.selfhost;

fn test_missing_config_keeps_legacy_mode(outer: goosetest::Test&) {
    let root = filesystem_support::project(selfhost_support::scratch(outer), "legacy");
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    assert(config::load(configuration, root) == 0);
    assert(!configuration.configured);
    assert(configuration.targets.len == 0);
}

fn test_cli_rejects_config_before_discovery(outer: goosetest::Test&) {
    let root = filesystem_support::project(selfhost_support::scratch(outer), "cli_bad_config");
    filesystem_support::write(root, "goosetest.json", "{\"version\":1,\"targets\":[],\"testRoots\":[]}");
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    options.project.append(root);
    options.command = arguments::Command.List;
    assert(cli::run(options) == 2);
}

fn test_cli_does_not_fall_back_for_valid_config(outer: goosetest::Test&) {
    let root = filesystem_support::project(selfhost_support::scratch(outer), "cli_valid_config");
    filesystem_support::write(
        root,
        "goosetest.json",
        "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}]}]}"
    );
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    options.project.append(root);
    options.command = arguments::Command.List;
    assert(cli::run(options) == 2);
}

fn test_example_and_optional_defaults(outer: goosetest::Test&) {
    let root = filesystem_support::project(selfhost_support::scratch(outer), "configured");
    filesystem_support::write(root, "goosetest.json", "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"goosetest_core.goose\",\"tests\":[{\"path\":\"tests/request\",\"kind\":\"unit\"}],\"exclude\":[\"tests/request/rejections/\",\"tests/request/example_test.goose\"],\"mirror\":{\"policy\":\"off\",\"pairs\":[]}}]}");
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    assert(config::load(configuration, root) == 0);
    assert(configuration.configured);
    assert(configuration.targets.len == 1);
    assert(config::text_value(configuration, configuration.targets[0].name) == "core");
    assert(config::text_value(configuration, configuration.targets[0].entry) == "goosetest_core.goose");
    assert(configuration.roots.len == 1);
    assert(configuration.roots[0].kind == config::TestKind.Unit);
    goosetest::assert_eq(outer, 2, configuration.exclusions.len);
    goosetest::assert_eq(outer, 0, configuration.pairs.len);
}

fn test_project_ancestor_with_spaces(outer: goosetest::Test&) {
    let parent = str(selfhost_support::scratch(outer), "/ancestor with spaces");
    assert(make_dir(parent));
    let root = filesystem_support::project(parent, "project");
    filesystem_support::write(root, "goosetest.json", "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}]}]}");
    assert(load_existing(root) == 0);
}

fn test_reject_duplicate_unknown_and_wrong_type(outer: goosetest::Test&) {
    let scratch = selfhost_support::scratch(outer);
    reject(scratch, "duplicate", "{\"version\":1,\"version\":1,\"targets\":[]}", "duplicate JSON object key");
    reject(scratch, "unknown", "{\"version\":1,\"targets\":[],\"testRoots\":[]}", "unknown top-level field");
    reject(scratch, "wrong_type", "{\"version\":true,\"targets\":[]}", "unsupported configuration version");
    reject(scratch, "empty_targets", "{\"version\":1,\"targets\":[]}", "targets must not be empty");
    let empty_tests = str(
        "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":",
        "\"root.goose\",\"tests\":[]}]}"
    );
    reject(scratch, "empty_tests", empty_tests, "tests must not be empty");
    let duplicate_name = str("{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"a.goose\",\"tests\":[{\"path\":\"tests/a\",\"kind\":\"unit\"}]},", "{\"name\":\"core\",\"entry\":\"b.goose\",\"tests\":[{\"path\":\"tests/b\",\"kind\":\"unit\"}]}]}");
    reject(scratch, "duplicate_name", duplicate_name, "duplicate target name");
    let bad_policy = str("{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}],", "\"mirror\":{\"policy\":\"sometimes\",\"pairs\":[]}}]}");
    reject(scratch, "bad_policy", bad_policy, "mirror policy must be off or strict");
    let bad_pair = str("{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}],", "\"mirror\":{\"policy\":\"strict\",\"pairs\":[{\"source\":\"src/core\",\"tests\":\"tests/missing\"}]}}]}");
    reject(scratch, "bad_pair", bad_pair, "mirror tests path must name a unit root");
}

fn test_reject_paths_and_root_ambiguity(outer: goosetest::Test&) {
    let scratch = selfhost_support::scratch(outer);
    reject(scratch, "traversal", "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"../root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}]}]}", "invalid project-relative Goose entry path");
    reject(scratch, "overlap", "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}]},{\"name\":\"other\",\"entry\":\"other.goose\",\"tests\":[{\"path\":\"tests/nested\",\"kind\":\"unit\"}]}]}", "test roots overlap");
}

fn test_path_and_name_limits(outer: goosetest::Test&) {
    assert(config::valid_target_name("a"));
    var maximum: u8[>..] = [];
    for _ in 0..48 {
        maximum.push('a');
    }
    assert(config::valid_target_name(maximum));
    var too_long: u8[>..] = [];
    for _ in 0..49 {
        too_long.push('a');
    }
    assert(!config::valid_target_name(too_long));
    assert(!config::valid_target_name("all"));
    assert(!config::valid_target_name("cache"));
    assert(config::valid_path("goosetest_core.goose", true, false));
    assert(config::valid_path("tests/request", false, false));
    assert(!config::valid_path("tests/../request", false, false));
    assert(!config::valid_path("/tests/request", false, false));
    assert(!config::valid_path("tests\\request", false, false));
    var max_path: u8[>..] = [];
    for _ in 0..4096 {
        max_path.push('a');
    }
    assert(config::valid_path(max_path, false, false));
    max_path.push('a');
    assert(!config::valid_path(max_path, false, false));
}

fn test_collection_limits(outer: goosetest::Test&) {
    let scratch = selfhost_support::scratch(outer);
    assert(load_status(scratch, "targets_exact", limit_document(64, 1, 0, 0)) == 0);
    assert(load_status(scratch, "targets_over", limit_document(65, 1, 0, 0)) == 2);
    assert(load_status(scratch, "roots_exact", limit_document(1, 64, 0, 0)) == 0);
    assert(load_status(scratch, "roots_over", limit_document(1, 65, 0, 0)) == 2);
    assert(load_status(scratch, "exclusions_exact", limit_document(1, 1, 256, 0)) == 0);
    assert(load_status(scratch, "exclusions_over", limit_document(1, 1, 257, 0)) == 2);
    assert(load_status(scratch, "pairs_exact", limit_document(1, 64, 0, 64)) == 0);
    assert(load_status(scratch, "pairs_over", limit_document(1, 64, 0, 65)) == 2);
}

fn test_configuration_byte_limit(outer: goosetest::Test&) {
    let scratch = selfhost_support::scratch(outer);
    let document = limit_document(1, 1, 0, 0);
    var exact: u8[>..] = [];
    exact.append(document);
    while exact.len < 1048576 {
        exact.push(' ');
    }
    assert(load_status(scratch, "bytes_exact", exact) == 0);
    exact.push(' ');
    assert(load_status(scratch, "bytes_over", exact) == 2);
}

fn reject(scratch: u8[:], name: u8[:], json: u8[:], expected: u8[:]) {
    let root = filesystem_support::project(scratch, name);
    filesystem_support::write(root, "goosetest.json", json);
    var before: u8[>..] = [];
    assert(list_dir(root, before));
    var before_src: u8[>..] = [];
    var before_test: u8[>..] = [];
    assert(list_dir(str(root, "/src"), before_src));
    assert(list_dir(str(root, "/test"), before_test));
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    assert(config::load(configuration, root) == 2);
    assert(!configuration.configured);
    assert(configuration.error.len > 0);
    assert(configuration.error == expected);
    assert(file_exists(str(root, "/goosetest.json")));
    var after: u8[>..] = [];
    assert(list_dir(root, after));
    assert(before == after);
    var after_src: u8[>..] = [];
    var after_test: u8[>..] = [];
    assert(list_dir(str(root, "/src"), after_src));
    assert(list_dir(str(root, "/test"), after_test));
    assert(before_src == after_src);
    assert(before_test == after_test);
}

fn load_status(scratch: u8[:], name: u8[:], json: u8[:]) -> i32 {
    let root = filesystem_support::project(scratch, name);
    filesystem_support::write(root, "goosetest.json", json);
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    return config::load(configuration, root);
}

fn load_existing(root: u8[:]) -> i32 {
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    return config::load(configuration, root);
}

fn limit_document(target_count: i64, root_count: i64, exclusion_count: i64, pair_count: i64) -> u8[>..] {
    var output: u8[>..] = [];
    output.append("{\"version\":1,\"targets\":[");
    for target in 0..target_count {
        if target > 0 {
            output.push(',');
        }
        append_target(output, target, root_count, exclusion_count, pair_count);
    }
    output.append("]}");
    return output;
}

fn append_target(output: u8[>..]&, target: i64, root_count: i64, exclusion_count: i64, pair_count: i64) {
    output.append(str("{\"name\":\"t", target, "\",\"entry\":\"entry_", target, ".goose\",\"tests\":["));
    for root in 0..root_count {
        if root > 0 {
            output.push(',');
        }
        output.append(str("{\"path\":\"tests/t", target, "_r", root, "\",\"kind\":\"unit\"}"));
    }
    output.push(']');
    if exclusion_count > 0 {
        output.append(",\"exclude\":[");
        for item in 0..exclusion_count {
            if item > 0 {
                output.push(',');
            }
            output.append(str("\"ignored_", item, "\""));
        }
        output.push(']');
    }
    if pair_count == 0 {
        output.append(",\"mirror\":{\"policy\":\"off\",\"pairs\":[]}");
    } else {
        output.append(",\"mirror\":{\"policy\":\"strict\",\"pairs\":[");
        for pair in 0..pair_count {
            if pair > 0 {
                output.push(',');
            }
            output.append(str("{\"source\":\"src/s", pair, "\",\"tests\":\"tests/t", target, "_r", pair, "\"}"));
        }
        output.append("]}");
    }
    output.push('}');
}
