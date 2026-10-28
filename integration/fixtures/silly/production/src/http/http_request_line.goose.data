// Strict request-line grammar; routing receives unchanged target bytes.
namespace silly;

import.http_head_types;
import.http_host;

fn parse_request_line(line: u8[:]) -> ParsedHead {
    let method_end = head_byte_index(line, ' ', 0);
    if method_end <= 0 || !valid_header_name(line[..method_end]) {
        return ParsedHead {
        };
    }
    let target_end = head_byte_index(line, ' ', method_end + 1);
    if target_end <= method_end + 1 {
        return ParsedHead {
        };
    }
    let version = line[target_end + 1..];
    if version != "HTTP/1.0" && version != "HTTP/1.1" {
        if valid_http_version(version) {
            return ParsedHead {
                result: HeadResult.UnsupportedVersion,
                ..
            };
        }
        return ParsedHead {
        };
    }
    var parsed = ParsedHead {
        result: HeadResult.Complete,
        method: line[..method_end],
        target: line[method_end + 1..target_end],
        http_minor: if version == "HTTP/1.0" {
            0
        } else {
            1
        },
        ..
    };
    parsed.result = validate_target(parsed);
    return parsed;
}

fn valid_http_version(version: u8[:]) -> bool {
    return version.len == 8 && version[..5] == "HTTP/" && version[6] == '.'
        && version[5] >= '0' && version[5] <= '9' && version[7] >= '0' && version[7] <= '9';
}

fn validate_target(parsed: ParsedHead&) -> HeadResult {
    if !valid_target_bytes(parsed.target) {
        return HeadResult.BadRequest;
    }
    if parsed.method == "CONNECT" {
        parsed.target_form = TargetForm.Authority;
        parsed.authority = parsed.target;
        return if valid_host(parsed.target) && target_has_port(parsed.target) {
            HeadResult.Complete
        } else {
            HeadResult.BadRequest
        };
    }
    if parsed.target == "*" {
        parsed.target_form = TargetForm.Asterisk;
        return if parsed.method == "OPTIONS" {
            HeadResult.Complete
        } else {
            HeadResult.BadRequest
        };
    }
    if parsed.target[0] == '/' {
        return validate_target_path(parsed.target);
    }
    var start = 0;
    if parsed.target.len >= 7 && header_name_equal(parsed.target[..7], "http://") {
        start = 7;
    } else if parsed.target.len >= 8 && header_name_equal(parsed.target[..8], "https://") {
        start = 8;
    } else {
        return HeadResult.BadRequest;
    }
    var end = start;
    while end < parsed.target.len && parsed.target[end] != '/' && parsed.target[end] != '?' {
        end += 1;
    }
    parsed.target_form = TargetForm.Absolute;
    parsed.authority = parsed.target[start..end];
    if !valid_host(parsed.authority) {
        return HeadResult.BadRequest;
    }
    return validate_target_path(parsed.target[end..]);
}

fn validate_target_path(path_query: u8[:]) -> HeadResult {
    for byte in path_query {
        if byte == '[' || byte == ']' {
            return HeadResult.BadRequest;
        }
    }
    return HeadResult.Complete;
}

fn target_has_port(target: u8[:]) -> bool {
    let colon = head_byte_index(target, ':', 0);
    if colon < 0 {
        return false;
    }
    if target[0] == '[' {
        let closing = head_byte_index(target, ']', 0);
        return closing >= 0 && closing + 2 < target.len && target[closing + 1] == ':';
    }
    return colon + 1 < target.len;
}

fn valid_target_bytes(target: u8[:]) -> bool {
    if target.len == 0 {
        return false;
    }
    for byte in target {
        if byte <= 32 || byte >= 127 || byte == '#' || byte == '\\'
            || byte == '"' || byte == '<' || byte == '>' || byte == '^' || byte == '`'
            || byte == '{' || byte == '|' || byte == '}' {
            return false;
        }
    }
    return true;
}

fn head_byte_index(input: u8[:], byte: u8, start: i64) -> i64 {
    for index in start..input.len {
        if input[index] == byte {
            return index;
        }
    }
    return -1;
}
