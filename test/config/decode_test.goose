// Schema decoding consumes the bounded parser's owned token table.
namespace config_decode_test;

import goosetest;
import src.config.decode;
import src.config.json;
import src.config.model;

fn test_version_and_targets_decode(outer: goosetest::Test&) {
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    var tokens: config::JsonToken[>..] = [];
    var reader = config::Reader {
        source: "{\"version\":1,\"targets\":[{\"name\":\"core\",\"entry\":\"root.goose\",\"tests\":[{\"path\":\"tests\",\"kind\":\"unit\"}]}]}",
        text: configuration.text,
        tokens: tokens,
    };
    config::parse_document(reader);
    assert(reader.error.len == 0);
    assert(config::decode_configuration(configuration, reader.tokens));
    assert(configuration.targets.len == 1);
    assert(configuration.roots.len == 1);
}
