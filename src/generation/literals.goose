// Encode bytes as short ordinary Goose literals; neither raw strings nor interpolation.
namespace generation;

import std;

fn encoded_byte(byte: u8) -> u8[>..] {
    var result: u8[>..] = [];
    if byte == '"' || byte == '\\' {
        result.push('\\');
        result.push(byte);
    } else if byte < 32 || byte >= 127 {
        let hex = "0123456789ABCDEF";
        result.append("\\x");
        result.push(hex[(byte / 16)as i64]);
        result.push(hex[(byte % 16)as i64]);
    } else {
        result.push(byte);
    }
    return result;
}

// Input bound guarantees at most 64 append lines, hence a function below 70 lines.
fn emit_text(out: u8[>..]&, name: u8[:], value: u8[:]) {
    assert(value.len <= 1024);
    format(out, "fn ", name, "() -> u8[>..] {\n    var text: u8[>..] = [];\n");
    var chunk: u8[>..<] = [];
    for byte in value {
        let encoded = encoded_byte(byte);
        if chunk.len + encoded.len > 64 {
            format(out, "    text.append(\"", chunk, "\");\n");
            chunk.clear();
        }
        chunk.append(encoded);
    }
    if chunk.len > 0 {
        format(out, "    text.append(\"", chunk, "\");\n");
    }
    out.append("    return text;\n}\n\n");
}
