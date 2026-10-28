// JSON syntax reader preserves nested containers and catches equivalent duplicate keys.
namespace config_json_test;

import goosetest;
import src.config.json;

fn test_nested_json_and_duplicate_detection(outer: goosetest::Test&) {
    var text: u8[>..] = [];
    var tokens: config::JsonToken[>..] = [];
    var reader = config::Reader {
        source: "{\"x\":[{\"y\":true}],\"z\":null}",
        text: text,
        tokens: tokens,
    };
    config::parse_document(reader);
    assert(reader.error.len == 0);
    assert(reader.tokens[0].kind == config::JsonKind.Object);
    var duplicate_text: u8[>..] = [];
    var duplicate_tokens: config::JsonToken[>..] = [];
    var duplicate = config::Reader {
        source: "{\"version\":1,\"\\u0076ersion\":2}",
        text: duplicate_text,
        tokens: duplicate_tokens,
    };
    config::parse_document(duplicate);
    assert(duplicate.error == "duplicate JSON object key");
}
