// URL decoding validates before mutation and keeps path and query policies independent.
namespace url_test;

import silly from "../../";

import std;

fn decoded(raw: u8[:], expected: u8[:], policy: silly::UrlDecodePolicy) {
    let measured = silly::measure_url(raw, policy);
    assert(measured.error == silly::UrlDecodeError.None);
    assert(measured.bytes == expected.len);
    var output: u8[>..] = [];
    output.append("prefix:");
    let cap = output.len + expected.len;
    if expected.len != 0 {
        assert(silly::decode_url(output, raw, cap - 1, policy) == silly::UrlDecodeError.Limit);
        assert(output == "prefix:");
    }
    assert(silly::decode_url(output, raw, cap, policy) == silly::UrlDecodeError.None);
    assert(output == str("prefix:", expected));
}

fn strict() {
    let policy = silly::UrlDecodePolicy {
        plus_as_space: true,
        ..
    };
    decoded("", "", policy);
    decoded("plain@example.test", "plain@example.test", policy);
    decoded("a+b%2Bc", "a b+c", policy);
    decoded("%00%ff%FF", "\x00\xff\xff", policy);
    decoded("caf%C3%A9", "caf\xc3\xa9", policy);
    decoded("raw\xc3\xa9", "raw\xc3\xa9", policy);
    decoded("%252F%2526%253D", "%2F%26%3D", policy);
    decoded("%26%3B%3D", "&;=", policy);
    decoded("%2b+%20", "+  ", policy);
    for raw in["%", "%0", "%xx", "ok%41then%4G", "%a%41"] {
        var output: u8[>..] = [];
        output.append("unchanged");
        assert(silly::measure_url(raw, policy).error == silly::UrlDecodeError.InvalidEscape);
        assert(silly::decode_url(output, raw, 128, policy) == silly::UrlDecodeError.InvalidEscape);
        assert(output == "unchanged");
    }
    assert(!silly::measure_url("plain", policy).transformed);
    assert(silly::measure_url("+", policy).transformed);
    assert(silly::measure_url("%41", policy).transformed);
}

fn literal() {
    let policy = silly::UrlDecodePolicy {
        plus_as_space: true,
        invalid_escape: silly::InvalidEscape.Literal,
    };
    decoded("%", "%", policy);
    decoded("%0", "%0", policy);
    decoded("%xx", "%xx", policy);
    decoded("%a%41", "%aA", policy);
    decoded("%%41+%2B%", "%A +%", policy);
    decoded("%252F%GG", "%2F%GG", policy);
    assert(!silly::measure_url("%GG", policy).transformed);
    assert(silly::measure_url("%GG%41", policy).transformed);
    // The explicit permissive query operation must not weaken the path decoder.
    var path: u8[>..] = [];
    assert(silly::decode_path(path, "%GG", 32) == silly::PathDecodeError.InvalidEscape);
    assert(path.len == 0);
}

fn path_and_limits() {
    var output: u8[>..] = [];
    assert(silly::decode_path(output, "a+b/%252F/%2f", 64) == silly::PathDecodeError.None);
    assert(output == "a+b/%2F//");
    let size = output.len;
    assert(silly::decode_path(output, "x", size) == silly::PathDecodeError.Limit);
    assert(silly::decode_path(output, "", size - 1) == silly::PathDecodeError.Limit);
    assert(silly::decode_path(output, "", -1) == silly::PathDecodeError.Limit);
    assert(output == "a+b/%2F//");
    let policy = silly::UrlDecodePolicy {
    };
    assert(!silly::measure_url("a+b", policy).transformed);
    assert(silly::decode_url(output, "", -1, policy) == silly::UrlDecodeError.Limit);
    output.clear();
    assert(silly::decode_path(output, "", 0) == silly::PathDecodeError.None);
    assert(silly::decode_path(output, "%41", 0) == silly::PathDecodeError.Limit);
    assert(output.len == 0);
    assert(silly::decode_path(output, "%41", 1) == silly::PathDecodeError.None);
    assert(output == "A");
}

fn::main() {
    url_test::strict();
    url_test::literal();
    url_test::path_and_limits();
    print("bounded URL and strict path decoding passed");
}
