// Bounded collection traversal; custom value format hooks run in isolated scratch storage.
namespace value_format;

import std;

fn append<T>(out: u8[>..]&, value: T, limit: i64) -> bool {
    if limit < out.len {
        return false;
    }
    return render(out, value, limit, false, 0);
}

fn append_text(out: u8[>..]&, value: const u8[:], limit: i64) -> bool {
    if out.len > limit || value.len > limit - out.len {
        return false;
    }
    out.append(value);
    return true;
}

// The integer witness selects array-to-slice overloads before this last-resort
// integer-to-float candidate (pinned spec 7.1). Bare generic overloads tie with
// slices, and otherwise capture fixed arrays before their slice conversion.
fn render<T>(out: u8[>..]&, value: T, limit: i64, nested: bool, fallback: f64) -> bool {
    var scratch: u8[>..] = [];
    format(scratch, value);
    return append_text(out, scratch, limit);
}

fn render<T>(out: u8[>..]&, value: const T[:], limit: i64, nested: bool, collection: i64) -> bool {
    return render_items(out, value, limit, nested);
}

fn render_items<T>(out: u8[>..]&, value: const T[:], limit: i64, nested: bool) -> bool {
    if !append_text(out, "[", limit) {
        return false;
    }
    for item,
    index in value {
        if index > 0 && !append_text(out, ", ", limit) {
            return false;
        }
        // Reserve the closing bracket before entering another element or user hook.
        if out.len >= limit || !render(out, item, limit - 1, true, 0) {
            return false;
        }
    }
    return append_text(out, "]", limit);
}

fn render_items(out: u8[>..]&, value: const u8[:], limit: i64, nested: bool) -> bool {
    if !nested {
        return append_text(out, value, limit);
    }
    if !append_text(out, "\"", limit) {
        return false;
    }
    for byte in value {
        if !escaped_byte(out, byte, limit - 1) {
            return false;
        }
    }
    return append_text(out, "\"", limit);
}

fn escaped_byte(out: u8[>..]&, byte: u8, limit: i64) -> bool {
    if byte == '\n' {
        return append_text(out, "\\n", limit);
    }
    if byte == '\r' {
        return append_text(out, "\\r", limit);
    }
    if byte == '\t' {
        return append_text(out, "\\t", limit);
    }
    if byte == '"' {
        return append_text(out, "\\\"", limit);
    }
    if byte == '\\' {
        return append_text(out, "\\\\", limit);
    }
    if out.len >= limit {
        return false;
    }
    out.push(byte);
    return true;
}
