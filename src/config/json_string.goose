// JSON string decoder validates UTF-8 and Unicode escapes.
namespace config;

import src.config.model;

fn parse_string(reader: Reader&) -> Span {
    reader.index += 1;
    let begin = reader.text.len;
    while reader.index < reader.source.len {
        let byte = reader.source[reader.index];
        reader.index += 1;
        if byte == '"' {
            return Span {
                offset: begin,
                length: reader.text.len - begin
            };
        }
        if byte < 32 {
            return string_error(reader, "control byte in JSON string");
        }
        if byte != '\\' {
            if !append_source_character(reader, byte) {
                return Span {
                    offset: 0,
                    length: 0
                };
            }
        } else if !parse_escape(reader) {
            return Span {
                offset: 0,
                length: 0
            };
        }
    }
    reader.error = "unterminated JSON string";
    return Span {
        offset: 0,
        length: 0
    };
}

fn append_source_character(reader: Reader&, byte: u8) -> bool {
    if byte < 0x80 {
        reader.text.push(byte);
        return true;
    }
    let width = utf8_width(reader.source, reader.index - 1);
    if width == 0 {
        reader.error = "invalid UTF-8 in JSON string";
        return false;
    }
    reader.text.push(byte);
    for _ in 1..width {
        reader.text.push(reader.source[reader.index]);
        reader.index += 1;
    }
    return true;
}

fn parse_escape(reader: Reader&) -> bool {
    if reader.index >= reader.source.len {
        reader.error = "unfinished JSON escape";
        return false;
    }
    let escape = reader.source[reader.index];
    reader.index += 1;
    if escape == '"' || escape == '\\' || escape == '/' {
        reader.text.push(escape);
    } else if escape == 'b' {
        reader.text.push(8);
    } else if escape == 'f' {
        reader.text.push(12);
    } else if escape == 'n' {
        reader.text.push(10);
    } else if escape == 'r' {
        reader.text.push(13);
    } else if escape == 't' {
        reader.text.push(9);
    } else if escape == 'u' {
        append_unicode_escape(reader);
    } else {
        reader.error = "invalid JSON escape";
        return false;
    }
    return reader.error.len == 0;
}

fn append_unicode_escape(reader: Reader&) {
    var code = read_hex_quad(reader);
    if code < 0 {
        return;
    }
    if code >= 0xd800 && code <= 0xdbff {
        if reader.index + 2 > reader.source.len || reader.source[reader.index..reader.index + 2] != "\\u" {
            reader.error = "unpaired Unicode surrogate";
            return;
        }
        reader.index += 2;
        let low = read_hex_quad(reader);
        if low < 0 {
            return;
        }
        if low < 0xdc00 || low > 0xdfff {
            reader.error = "unpaired Unicode surrogate";
            return;
        }
        code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
    } else if code >= 0xdc00 && code <= 0xdfff {
        reader.error = "unpaired Unicode surrogate";
        return;
    }
    append_codepoint(reader, code);
}

fn read_hex_quad(reader: Reader&) -> i64 {
    if reader.index + 4 > reader.source.len {
        reader.error = "short Unicode escape";
        return -1;
    }
    var value: i64 = 0;
    for _ in 0..4 {
        let digit = hex_digit(reader.source[reader.index]);
        reader.index += 1;
        if digit < 0 {
            reader.error = "invalid Unicode escape";
            return -1;
        }
        value = value * 16 + digit;
    }
    return value;
}

fn hex_digit(byte: u8) -> i64 {
    if byte >= '0' && byte <= '9' {
        return byte - '0';
    }
    if byte >= 'a' && byte <= 'f' {
        return byte - 'a' + 10;
    }
    if byte >= 'A' && byte <= 'F' {
        return byte - 'A' + 10;
    }
    return -1;
}

fn append_codepoint(reader: Reader&, code: i64) {
    if code <= 0x7f {
        reader.text.push(code as u8);
    } else if code <= 0x7ff {
        reader.text.push((0xc0 | (code >> 6))as u8);
        reader.text.push((0x80 | (code & 63))as u8);
    } else if code <= 0xffff {
        reader.text.push((0xe0 | (code >> 12))as u8);
        reader.text.push((0x80 | ((code >> 6) & 63))as u8);
        reader.text.push((0x80 | (code & 63))as u8);
    } else {
        reader.text.push((0xf0 | (code >> 18))as u8);
        reader.text.push((0x80 | ((code >> 12) & 63))as u8);
        reader.text.push((0x80 | ((code >> 6) & 63))as u8);
        reader.text.push((0x80 | (code & 63))as u8);
    }
}

fn utf8_width(source: u8[:], start: i64) -> i64 {
    let first = source[start];
    let width = if first >= 0xc2 && first <= 0xdf {
        2
    } else if first >= 0xe0 && first <= 0xef {
        3
    } else if first >= 0xf0 && first <= 0xf4 {
        4
    } else {
        0
    };
    if width == 0 || start + width > source.len {
        return 0;
    }
    for offset in 1..width {
        let next = source[start + offset];
        if next < 0x80 || next > 0xbf {
            return 0;
        }
    }
    let second = source[start + 1];
    if (first == 0xe0 && second < 0xa0) || (first == 0xed && second > 0x9f)
        || (first == 0xf0 && second < 0x90) || (first == 0xf4 && second > 0x8f) {
        return 0;
    }
    return width;
}

fn string_error(reader: Reader&, message: u8[:]) -> Span {
    reader.error = message;
    return Span {
        offset: 0,
        length: 0
    };
}
