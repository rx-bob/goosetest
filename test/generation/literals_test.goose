// Literal encoding preserves bytes while preventing source injection.
namespace literals_test;

import goosetest.src.generation.literals;

fn test_bytes() {
    assert(generation::encoded_byte('"') == "\\\"");
    assert(generation::encoded_byte('\\') == "\\\\");
    assert(generation::encoded_byte('\n') == "\\x0A");
    assert(generation::encoded_byte(0) == "\\x00");
    assert(generation::encoded_byte(255) == "\\xFF");
    assert(generation::encoded_byte('A') == "A");
}

fn test_function_bounds() {
    var value: u8[>..] = [];
    for index in 0..1024 {
        value.push(0);
    }
    var out: u8[>..] = [];
    generation::emit_text(out, "text", value);
    var lines: i64 = 0;
    var column: i64 = 0;
    for byte in out {
        if byte == '\n' {
            lines += 1;
            column = 0;
        }
        else {
            column += 1;
            assert(column <= 120);
        }
    }
    assert(lines <= 70);
}
