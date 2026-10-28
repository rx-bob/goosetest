// Bounded JSON syntax reader preserves decoded keys for duplicate detection.
namespace config;

import src.config.json_string;
import src.config.model;

fn parse_document(reader: Reader&) {
    skip_space(reader);
    if reader.index >= reader.source.len {
        reader.error = "empty JSON document";
        return;
    }
    parse_value(reader, 0);
    skip_space(reader);
    if reader.error.len == 0 && reader.index != reader.source.len {
        reader.error = "trailing bytes after JSON value";
    }
    if reader.error.len == 0 && (reader.tokens.len == 0 || reader.tokens[0].kind != JsonKind.Object) {
        reader.error = "top level must be an object";
    }
    if reader.error.len == 0 {
        reject_duplicate_keys(reader);
    }
}

fn skip_space(reader: Reader&) {
    while reader.index < reader.source.len {
        let byte = reader.source[reader.index];
        if byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n' {
            reader.index += 1;
        } else {
            return;
        }
    }
}

recursive fn parse_value(reader: Reader&, depth: i64) -> i64 {
    skip_space(reader);
    if reader.error.len > 0 {
        return -1;
    }
    if depth > 64 {
        reader.error = "JSON nesting exceeds 64";
        return -1;
    }
    if reader.index >= reader.source.len {
        reader.error = "expected JSON value";
        return -1;
    }
    let start = reader.tokens.len;
    let byte = reader.source[reader.index];
    if byte == '{' {
        parse_object(reader, start, depth);
    } else if byte == '[' {
        parse_array(reader, start, depth);
    } else if byte == '"' {
        let value = parse_string(reader);
        if reader.error.len > 0 {
            return start;
        }
        reader.tokens.push(JsonToken {
                kind: JsonKind.String,
                text: value,
                end: reader.tokens.len + 1
            });
    } else {
        parse_literal(reader, start);
        if reader.error.len > 0 {
            return start;
        }
    }
    if reader.error.len > 0 {
        return start;
    }
    reader.tokens[start].end = reader.tokens.len;
    return start;
}

fn parse_object(reader: Reader&, start: i64, depth: i64) {
    push_container(reader, JsonKind.Object);
    reader.index += 1;
    skip_space(reader);
    if take(reader, '}') {
        reader.tokens[start].end = reader.tokens.len;
        return;
    }
    loop {
        if !parse_member(reader, depth) {
            return;
        }
        skip_space(reader);
        if take(reader, '}') {
            break;
        }
        if !take(reader, ',') {
            reader.error = "expected ',' or '}' in object";
            return;
        }
    }
    reader.tokens[start].end = reader.tokens.len;
}

fn parse_member(reader: Reader&, depth: i64) -> bool {
    skip_space(reader);
    if reader.index >= reader.source.len || reader.source[reader.index] != '"' {
        reader.error = "object key must be a string";
        return false;
    }
    let key = parse_string(reader);
    if reader.error.len > 0 {
        return false;
    }
    reader.tokens.push(JsonToken {
            kind: JsonKind.String,
            text: key,
            end: reader.tokens.len + 1
        });
    skip_space(reader);
    if !take(reader, ':') {
        reader.error = "expected ':' after object key";
        return false;
    }
    parse_value(reader, depth + 1);
    return reader.error.len == 0;
}

fn parse_array(reader: Reader&, start: i64, depth: i64) {
    push_container(reader, JsonKind.Array);
    reader.index += 1;
    skip_space(reader);
    if take(reader, ']') {
        reader.tokens[start].end = reader.tokens.len;
        return;
    }
    loop {
        parse_value(reader, depth + 1);
        if reader.error.len > 0 {
            return;
        }
        skip_space(reader);
        if take(reader, ']') {
            break;
        }
        if !take(reader, ',') {
            reader.error = "expected ',' or ']' in array";
            return;
        }
    }
    reader.tokens[start].end = reader.tokens.len;
}

fn push_container(reader: Reader&, kind: JsonKind) {
    reader.tokens.push(JsonToken {
            kind: kind,
            text: Span {
                offset: 0,
                length: 0
            },
            end: 0
        });
}

fn reject_duplicate_keys(reader: Reader&) {
    for object in 0..reader.tokens.len {
        if reader.tokens[object].kind != JsonKind.Object {
            continue;
        }
        var key_index = object + 1;
        let end = reader.tokens[object].end;
        while key_index < end {
            let value_index = key_index + 1;
            var prior = object + 1;
            while prior < key_index {
                let prior_value = prior + 1;
                let left = reader.tokens[prior].text;
                let right = reader.tokens[key_index].text;
                let left_text = reader.text[left.offset..left.offset + left.length];
                let right_text = reader.text[right.offset..right.offset + right.length];
                if equal(left_text, right_text) {
                    reader.error = "duplicate JSON object key";
                    return;
                }
                prior = reader.tokens[prior_value].end;
            }
            key_index = reader.tokens[value_index].end;
        }
    }
}

fn take(reader: Reader&, byte: u8) -> bool {
    if reader.index < reader.source.len && reader.source[reader.index] == byte {
        reader.index += 1;
        return true;
    }
    return false;
}

fn parse_literal(reader: Reader&, start: i64) {
    let remaining = reader.source[reader.index..];
    if starts(remaining, "true") {
        reader.index += 4;
        reader.tokens.push(JsonToken {
                kind: JsonKind.True,
                text: Span {
                    offset: 0,
                    length: 0
                },
                end: start + 1
            });
    } else if starts(remaining, "false") {
        reader.index += 5;
        reader.tokens.push(JsonToken {
                kind: JsonKind.False,
                text: Span {
                    offset: 0,
                    length: 0
                },
                end: start + 1
            });
    } else if starts(remaining, "null") {
        reader.index += 4;
        reader.tokens.push(JsonToken {
                kind: JsonKind.Null,
                text: Span {
                    offset: 0,
                    length: 0
                },
                end: start + 1
            });
    } else if number_start(reader.source[reader.index]) {
        let begin = reader.index;
        while reader.index < reader.source.len {
            let c = reader.source[reader.index];
            if (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E' {
                reader.index += 1;
            } else {
                break;
            }
        }
        if !valid_number(reader.source[begin..reader.index]) {
            reader.error = "invalid JSON number";
            return;
        }
        let number = Span {
            offset: reader.text.len,
            length: reader.index - begin
        };
        reader.text.append(reader.source[begin..reader.index]);
        reader.tokens.push(JsonToken {
                kind: JsonKind.Number,
                text: number,
                end: start + 1
            });
    } else {
        reader.error = "invalid JSON value";
    }
}

fn number_start(byte: u8) -> bool {
    return (byte >= '0' && byte <= '9') || byte == '-';
}

fn valid_number(value: u8[:]) -> bool {
    if value.len == 0 {
        return false;
    }
    var index: i64 = 0;
    if value[index] == '-' {
        index += 1;
        if index == value.len {
            return false;
        }
    }
    if value[index] == '0' {
        index += 1;
        if index < value.len && value[index] >= '0' && value[index] <= '9' {
            return false;
        }
    } else {
        if value[index] < '1' || value[index] > '9' {
            return false;
        }
        while index < value.len && value[index] >= '0' && value[index] <= '9' {
            index += 1;
        }
    }
    if index < value.len && value[index] == '.' {
        index += 1;
        let begin = index;
        while index < value.len && value[index] >= '0' && value[index] <= '9' {
            index += 1;
        }
        if begin == index {
            return false;
        }
    }
    if index < value.len && (value[index] == 'e' || value[index] == 'E') {
        index += 1;
        if index < value.len && (value[index] == '+' || value[index] == '-') {
            index += 1;
        }
        let begin = index;
        while index < value.len && value[index] >= '0' && value[index] <= '9' {
            index += 1;
        }
        if begin == index {
            return false;
        }
    }
    return index == value.len;
}

fn starts(value: u8[:], prefix: u8[:]) -> bool {
    return value.len >= prefix.len && value[..prefix.len] == prefix;
}

fn equal(left: u8[:], right: u8[:]) -> bool {
    return left.len == right.len && left == right;
}
