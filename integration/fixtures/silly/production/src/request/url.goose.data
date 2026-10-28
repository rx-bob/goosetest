// Byte-oriented URL decoding. Policy never crosses implicitly from query to path decoding.
namespace silly;

enum InvalidEscape {
    Strict,
    Literal,
}
struct UrlDecodePolicy {
    plus_as_space: bool = false,
    invalid_escape: InvalidEscape = InvalidEscape.Strict,
}
enum UrlDecodeError {
    None,
    InvalidEscape,
    Limit,
}
struct UrlDecodedSize {
    error: UrlDecodeError = UrlDecodeError.None,
    bytes: i64 = 0,
    transformed: bool = false,
}
enum PathDecodeError {
    None,
    InvalidEscape,
    Limit,
}

fn path_hex(byte: u8) -> i32 {
    if byte >= '0' && byte <= '9' {
        return byte - '0';
    }
    if byte >= 'a' && byte <= 'f' {
        return (byte - 'a')as i32 + 10;
    }
    if byte >= 'A' && byte <= 'F' {
        return (byte - 'A')as i32 + 10;
    }
    return -1;
}

fn url_escape_valid(raw: u8[:], cursor: i64) -> bool {
    return raw.len - cursor >= 3 && path_hex(raw[cursor + 1]) >= 0 && path_hex(raw[cursor + 2]) >= 0;
}

// No allocation. Decoded bytes never exceed input bytes, including literal malformed escapes.
fn measure_url(raw: u8[:], policy: UrlDecodePolicy) -> UrlDecodedSize {
    var result = UrlDecodedSize {
    };
    var cursor: i64 = 0;
    while cursor < raw.len {
        if raw[cursor] == '%' {
            if url_escape_valid(raw, cursor) {
                result.transformed = true;
                cursor += 2;
            } else if policy.invalid_escape == InvalidEscape.Strict {
                return UrlDecodedSize {
                    error: UrlDecodeError.InvalidEscape,
                    ..
                };
            }
        } else if raw[cursor] == '+' && policy.plus_as_space {
            result.transformed = true;
        }
        result.bytes += 1;
        cursor += 1;
    }
    return result;
}

// Validate the complete operation before appending. cap includes existing output bytes.
fn decode_url(out: u8[>..]&, raw: u8[:], cap: i64, policy: UrlDecodePolicy) -> UrlDecodeError {
    if cap < 0 || out.len > cap {
        return UrlDecodeError.Limit;
    }
    let measured = measure_url(raw, policy);
    if measured.error != UrlDecodeError.None {
        return measured.error;
    }
    if measured.bytes > cap - out.len {
        return UrlDecodeError.Limit;
    }
    var cursor: i64 = 0;
    while cursor < raw.len {
        if raw[cursor] == '%' && url_escape_valid(raw, cursor) {
            out.push((path_hex(raw[cursor + 1]) * 16 + path_hex(raw[cursor + 2]))as u8);
            cursor += 3;
        } else {
            out.push(if raw[cursor] == '+' && policy.plus_as_space {
                    ' '
                } else {
                    raw[cursor]
                });
            cursor += 1;
        }
    }
    return UrlDecodeError.None;
}

// Paths always use strict percent decoding, preserve '+', and consume only original input.
fn decode_path(out: u8[>..]&, raw: u8[:], cap: i64) -> PathDecodeError {
    let error = decode_url(out, raw, cap, UrlDecodePolicy {
        });
    return match error {
        None => {
            PathDecodeError.None
        },
        InvalidEscape => {
            PathDecodeError.InvalidEscape
        },
        Limit => {
            PathDecodeError.Limit
        },
    };
}
