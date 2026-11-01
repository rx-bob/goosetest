// Goose tokenizer shared by the formatter and linter.
namespace lexer;

import lexer_scan;

let IDENT: i32 = 1;
let NUMBER: i32 = 2;
let STRING: i32 = 3;
let CHARACTER: i32 = 4;
let OPERATOR: i32 = 5;
let PUNCTUATION: i32 = 6;
let COMMENT: i32 = 7;
let NEWLINE: i32 = 8;

struct Token {
    kind: i32,
    text: const u8[:],
    line: i64,
    column: i64,
    end_line: i64,
    end_column: i64,
    start: i64,
    end: i64,
}

struct Position {
    offset: i64,
    line: i64,
    column: i64,
}

fn position(offset: i64, line: i64, column: i64) -> Position {
    return Position {
        offset: offset,
        line: line,
        column: column
    };
}

fn make_token(source: const u8[:], kind: i32, start: Position, end: Position) -> Token {
    return Token {
        kind: kind,
        text: source[start.offset..end.offset],
        line: start.line,
        column: start.column,
        end_line: end.line,
        end_column: end.column,
        start: start.offset,
        end: end.offset,
    };
}

fn identifier_start(byte: u8) -> bool {
    return (byte >= 'a' && byte <= 'z')
        || (byte >= 'A' && byte <= 'Z')
        || byte == '_';
}

fn identifier_byte(byte: u8) -> bool {
    return identifier_start(byte) || (byte >= '0' && byte <= '9');
}

fn decimal_digit(byte: u8) -> bool {
    return (byte >= '0' && byte <= '9') || byte == '_';
}

fn hexadecimal_digit(byte: u8) -> bool {
    return decimal_digit(byte) || (byte >= 'a' && byte <= 'f')
        || (byte >= 'A' && byte <= 'F');
}

fn scan_number(source: const u8[:], start: i64) -> i64 {
    var at = start;
    if at + 1 < source.len && source[at] == '0'
        && (source[at + 1] == 'x' || source[at + 1] == 'X') {
        at += 2;
        while at < source.len && hexadecimal_digit(source[at]) {
            at += 1;
        }
        if at + 1 < source.len && source[at] == '.' && source[at + 1] != '.'
            && hexadecimal_digit(source[at + 1]) {
            at += 1;
            while at < source.len && hexadecimal_digit(source[at]) {
                at += 1;
            }
        }
        if at < source.len && (source[at] == 'p' || source[at] == 'P') {
            at += 1;
            if at < source.len && (source[at] == '+' || source[at] == '-') {
                at += 1;
            }
            while at < source.len && decimal_digit(source[at]) {
                at += 1;
            }
        }
        return at;
    }

    while at < source.len && decimal_digit(source[at]) {
        at += 1;
    }
    if at + 1 < source.len && source[at] == '.' && source[at + 1] != '.'
        && source[at + 1] >= '0' && source[at + 1] <= '9' {
        at += 1;
        while at < source.len && decimal_digit(source[at]) {
            at += 1;
        }
    }
    if at < source.len && (source[at] == 'e' || source[at] == 'E') {
        at += 1;
        if at < source.len && (source[at] == '+' || source[at] == '-') {
            at += 1;
        }
        while at < source.len && decimal_digit(source[at]) {
            at += 1;
        }
    }
    return at;
}

fn whitespace(byte: u8) -> bool {
    return byte == ' ' || byte == '\t' || byte == 11 || byte == 12;
}

fn newline(source: const u8[:], at: i64) -> i64 {
    if source[at] == '\r' && at + 1 < source.len && source[at + 1] == '\n' {
        return at + 2;
    }
    return at + 1;
}

fn long_operator_at(source: const u8[:], at: i64) -> const u8[:] {
    let rest = source[at..];
    if rest.starts_with("<<=") {
        return "<<=";
    }
    if rest.starts_with(">>=") {
        return ">>=";
    }
    if rest.starts_with("...") {
        return "...";
    }
    if rest.starts_with("..=") {
        return "..=";
    }
    if rest.starts_with("::") {
        return "::";
    }
    if rest.starts_with("->") {
        return "->";
    }
    if rest.starts_with("=>") {
        return "=>";
    }
    if rest.starts_with(".=") {
        return ".=";
    }
    if rest.starts_with("==") {
        return "==";
    }
    if rest.starts_with("!=") {
        return "!=";
    }
    if rest.starts_with("<=") {
        return "<=";
    }
    if rest.starts_with(">=") {
        return ">=";
    }
    if rest.starts_with("&&") {
        return "&&";
    }
    if rest.starts_with("||") {
        return "||";
    }
    return "";
}

fn operator_at(source: const u8[:], at: i64) -> const u8[:] {
    let long = long_operator_at(source, at);
    if long.len > 0 {
        return long;
    }
    let rest = source[at..];
    if rest.starts_with("++") {
        return "++";
    }
    if rest.starts_with("--") {
        return "--";
    }
    if rest.starts_with("+=") {
        return "+=";
    }
    if rest.starts_with("-=") {
        return "-=";
    }
    if rest.starts_with("*=") {
        return "*=";
    }
    if rest.starts_with("/=") {
        return "/=";
    }
    if rest.starts_with("%=") {
        return "%=";
    }
    if rest.starts_with("&=") {
        return "&=";
    }
    if rest.starts_with("|=") {
        return "|=";
    }
    if rest.starts_with("^=") {
        return "^=";
    }
    if rest.starts_with("<<") {
        return "<<";
    }
    if rest.starts_with(">>") {
        return ">>";
    }
    if rest.starts_with("..") {
        return "..";
    }
    if source[at] == '=' || source[at] == '+' || source[at] == '-'
        || source[at] == '*' || source[at] == '/' || source[at] == '%'
        || source[at] == '&' || source[at] == '|' || source[at] == '^'
        || source[at] == '<' || source[at] == '>' || source[at] == '!'
        || source[at] == '~' || source[at] == '?' {
        return source[at..at + 1];
    }
    return "";
}

fn lex(source: const u8[:]) -> Token[>..] {
    var tokens: Token[>..] = [];
    var cursor = position(0, 1, 1);
    if source.len >= 3 && source[0] == 0xEF && source[1] == 0xBB && source[2] == 0xBF {
        cursor.offset = 3;
    }
    while cursor.offset < source.len {
        let byte = source[cursor.offset];
        if whitespace(byte) {
            cursor.offset += 1;
            cursor.column += 1;
            continue;
        }
        let start = cursor;
        if byte == '\r' || byte == '\n' {
            cursor.offset = newline(source, cursor.offset);
            cursor.line += 1;
            cursor.column = 1;
            tokens.push(make_token(source, NEWLINE, start, cursor));
            continue;
        }
        var kind = scan_comment(source, cursor);
        if kind == 0 {
            kind = scan_raw_string(source, cursor);
        }
        if kind == 0 {
            kind = scan_quoted(source, cursor);
        }
        if kind == 0 {
            kind = scan_atom(source, cursor);
        }
        tokens.push(make_token(source, kind, start, cursor));
    }
    return tokens;
}
