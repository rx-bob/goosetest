// Bounded ordered header metadata. Owned output uses offsets into a separate byte owner.
namespace silly;

import std;

struct HeaderView {
    name: const u8[:],
    value: const u8[:],
}

struct HeaderField {
    name_start: i64,
    name_bytes: i64,
    value_start: i64,
    value_bytes: i64,
}

struct HeaderLimits {
    count_max: i64 = 64,
    bytes_max: i64 = 16384,
}

enum HeaderResult {
    Ok,
    CountLimit,
    BytesLimit,
    InvalidName,
    InvalidValue,
    InvalidLimits,
}

// Failure leaves both owners unchanged. Callers must enforce their response lifecycle.
fn append_header(
    fields: HeaderField[>..]&,
    storage: u8[>..]&,
    name: u8[:],
    value: u8[:],
    limits: HeaderLimits
) -> HeaderResult {
    if limits.count_max < 0 || limits.bytes_max < 0 {
        return HeaderResult.InvalidLimits;
    }
    if fields.len >= limits.count_max {
        return HeaderResult.CountLimit;
    }
    if storage.len > limits.bytes_max || name.len > limits.bytes_max - storage.len {
        return HeaderResult.BytesLimit;
    }
    if value.len > limits.bytes_max - storage.len - name.len {
        return HeaderResult.BytesLimit;
    }
    if !valid_header_name(name) {
        return HeaderResult.InvalidName;
    }
    if !valid_header_value(value) {
        return HeaderResult.InvalidValue;
    }
    let field = HeaderField {
        name_start: storage.len,
        name_bytes: name.len,
        value_start: storage.len + name.len,
        value_bytes: value.len,
    };
    storage.append(name);
    storage.append(value);
    fields.push(field);
    return HeaderResult.Ok;
}

// Views pin storage until their scope ends; never reset storage while a view lives.
fn header_view(fields: HeaderField[:], storage: u8[:], index: i64) -> HeaderView {
    assert(index >= 0);
    assert(index < fields.len);
    let field = fields[index];
    assert(field.name_start >= 0);
    assert(field.name_bytes >= 0);
    assert(field.name_start <= storage.len);
    assert(field.name_bytes <= storage.len - field.name_start);
    assert(field.value_start >= 0);
    assert(field.value_bytes >= 0);
    assert(field.value_start <= storage.len);
    assert(field.value_bytes <= storage.len - field.value_start);
    return HeaderView {
        name: storage[field.name_start..field.name_start + field.name_bytes],
        value: storage[field.value_start..field.value_start + field.value_bytes],
    };
}

// Pass the previous index plus one to visit repeated fields in wire/insertion order.
fn find_header(headers: HeaderView[:], name: u8[:], start: i64 = 0) -> i64 {
    if start < 0 || start >= headers.len {
        return -1;
    }
    for index in start..headers.len {
        if header_name_equal(headers[index].name, name) {
            return index;
        }
    }
    return -1;
}

fn find_header(fields: HeaderField[:], storage: u8[:], name: u8[:], start: i64 = 0) -> i64 {
    if start < 0 || start >= fields.len {
        return -1;
    }
    for index in start..fields.len {
        let field = header_view(fields, storage, index);
        if header_name_equal(field.name, name) {
            return index;
        }
    }
    return -1;
}

fn header_name_equal(left: u8[:], right: u8[:]) -> bool {
    if left.len != right.len {
        return false;
    }
    for index in left.len {
        if header_lower(left[index]) != header_lower(right[index]) {
            return false;
        }
    }
    return true;
}

fn valid_header_name(name: u8[:]) -> bool {
    if name.len == 0 {
        return false;
    }
    for byte in name {
        if !header_token_byte(byte) {
            return false;
        }
    }
    return true;
}

fn valid_header_value(value: u8[:]) -> bool {
    for byte in value {
        if (byte < 32 && byte != '\t') || byte == 127 {
            return false;
        }
    }
    return true;
}

fn header_lower(byte: u8) -> u8 {
    if byte >= 'A' && byte <= 'Z' {
        return byte + 32;
    }
    return byte;
}

fn header_token_byte(byte: u8) -> bool {
    if (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') {
        return true;
    }
    if byte >= '0' && byte <= '9' {
        return true;
    }
    for punctuation in "!#$%&'*+-.^_`|~" {
        if byte == punctuation {
            return true;
        }
    }
    return false;
}
