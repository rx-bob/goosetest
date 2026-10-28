// Object field access walks complete nested token spans and rejects unknown keys.
namespace config_decode_fields_test;

import goosetest;
import src.config.decode_fields;
import src.config.json;
import src.config.model;

fn test_member_and_unknown_field_scan(outer: goosetest::Test&) {
    var text: u8[>..] = [];
    var targets: config::Target[>..] = [];
    var roots: config::TestRoot[>..] = [];
    var exclusions: config::Exclusion[>..] = [];
    var pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(text, targets, roots, exclusions, pairs);
    var tokens: config::JsonToken[>..] = [];
    var reader = config::Reader {
        source: "{\"version\":1,\"targets\":[]}",
        text: configuration.text,
        tokens: tokens,
    };
    config::parse_document(reader);
    assert(config::member(reader.tokens, configuration.text, 0, "version") == 2);
    assert(!config::has_unknown(configuration, reader.tokens, 0, config::AllowedFields {
            a: "version",
            b: "targets",
            c: "",
            d: "",
            e: ""
        }));
    assert(config::has_unknown(configuration, reader.tokens, 0, config::AllowedFields {
            a: "version",
            b: "wrong",
            c: "",
            d: "",
            e: ""
        }));
}
