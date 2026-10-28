// Authority syntax checks remain pure Goose and independent of DNS/network availability.
namespace http_host_test;

import silly from "../../";

import std;

fn valid_hosts() {
    for value in["localhost", "example.test:80", "example.test.:65535", "127.0.0.1:0", "percent%2dname",
        "[::]", "[::1]:8080", "[2001:db8::1]", "[1:2:3:4:5:6:7:8]", "[::ffff:192.0.2.1]",
        "[1:2:3:4:5:6:192.0.2.1]", "[v1.example:token]:443", "[Vf.host]"] {
        if !silly::valid_host(value) {
            print("unexpected authority rejection: ", value);
            assert(false);
        }
    }
}

fn invalid_hosts() {
    for value in["", ":80", "host:", "host:+80", "host:65536", "host:999999999999999999999",
        "host:80:90", "bad host", "bad\thost", "user@host", "host/path", "host?query", "host#fragment",
        "a,b", "host%", "host%0", "host%GG", "[]", "[1]", "[::1", "[::1]extra", "[::1]:",
        "[1:2:3:4:5:6:7]", "[1:2:3:4:5:6:7:8:9]", "[1:2:3:4:5:6:7::8]", "[::1::2]",
        "[:::1]", "[1:::]", "[12345::]", "[gg::]", "[::ffff:256.1.2.3]", "[::ffff:01.2.3.4]",
        "[::ffff:1.2.3]", "[::ffff:1.2.3.4:5]", "[v.host]", "[v1.]", "[v1.host%20]",
        "[fe80::1%eth0]"] {
        if silly::valid_host(value) {
            print("unexpected authority acceptance: ", value);
            assert(false);
        }
    }
}

fn target_syntax() {
    for target in["HTTP://example.test/path?x=%2f", "HtTpS://[::1]:443/path", "/path?raw=%GG"] {
        let line = str("GET ", target, " HTTP/1.1");
        let parsed = silly::parse_request_line(line);
        assert(parsed.result == silly::HeadResult.Complete);
        assert(parsed.target == target);
    }
    let invalid = "\"<>^`{|}\\#";
    for index in invalid.len {
        let target = str("/bad", invalid[index..index + 1], "path");
        let line = str("GET ", target, " HTTP/1.1");
        let parsed = silly::parse_request_line(line);
        assert(parsed.result == silly::HeadResult.BadRequest);
    }
    for target in["/bad[path", "/bad]path", "/?x=[value]", "http://host/bad[path",
        "http://[::1]/?x=value]", "https://host?x=[value"] {
        let line = str("GET ", target, " HTTP/1.1");
        let parsed = silly::parse_request_line(line);
        assert(parsed.result == silly::HeadResult.BadRequest);
    }
}

fn::main() {
    http_host_test::valid_hosts();
    http_host_test::invalid_hosts();
    http_host_test::target_syntax();
    print("HTTP authority syntax passed");
}
