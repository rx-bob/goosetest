// String decoder handles escaped Unicode code points and rejects malformed UTF-8.
namespace config_json_string_test;

import goosetest;
import src.config.json_string;

fn test_string_escape_decode(outer: goosetest::Test&) {
    var text: u8[>..] = [];
    var tokens: config::JsonToken[>..] = [];
    var reader = config::Reader {
        source: "\"quote: \\\" smile: \\uD83D\\uDE42\"",
        text: text,
        tokens: tokens,
    };
    let value = config::parse_string(reader);
    assert(reader.error.len == 0);
    assert(reader.index == reader.source.len);
    assert(reader.text[value.offset..value.offset + value.length] == "quote: \" smile: 🙂");
}

fn test_invalid_utf8_rejected(outer: goosetest::Test&) {
    var source: u8[>..] = [];
    source.append("{\"x\":\"");
    source.push(0xff);
    source.append("\"}");
    var text: u8[>..] = [];
    var tokens: config::JsonToken[>..] = [];
    var reader = config::Reader {
        source: source,
        text: text,
        tokens: tokens
    };
    config::parse_document(reader);
    assert(reader.error == "invalid UTF-8 in JSON string");
}
