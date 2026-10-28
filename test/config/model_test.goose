// Configuration-owned spans always point into the decoded text arena.
namespace config_model_test;

import goosetest;
import src.config.model;

fn test_owned_model(outer: goosetest::Test&) {
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    configuration.text.append("core");
    let name = config::Span {
        offset: 0,
        length: 4
    };
    configuration.targets.push(config::Target {
            name: name,
            entry: name,
            root_start: 0,
            root_count: 0,
            exclusion_start: 0,
            exclusion_count: 0,
            pair_start: 0,
            pair_count: 0,
            policy: config::MirrorPolicy.Off,
        });
    assert(config::text_value(configuration, configuration.targets[0].name) == "core");
    assert(configuration.targets[0].policy == config::MirrorPolicy.Off);
}
