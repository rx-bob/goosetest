// Literal and comment scanners.
namespace lexer;

fn scan_comment(source: const u8[:], cursor: Position&) -> i32 {
    if cursor.offset + 1 < source.len && source[cursor.offset] == '/' && source[cursor.offset + 1] == '/' {
        cursor.offset += 2;
        cursor.column += 2;
        while cursor.offset < source.len && source[cursor.offset] != '\r' && source[cursor.offset] != '\n' {
            cursor.offset += 1;
            cursor.column += 1;
        }
        return COMMENT;
    }

    if cursor.offset + 1 < source.len && source[cursor.offset] == '/' && source[cursor.offset + 1] == '*' {
        cursor.offset += 2;
        cursor.column += 2;
        var nesting: i64 = 1;
        while cursor.offset < source.len && nesting > 0 {
            if cursor.offset + 1 < source.len && source[cursor.offset] == '/' && source[cursor.offset + 1] == '*' {
                nesting += 1;
                cursor.offset += 2;
                cursor.column += 2;
            } else if cursor.offset + 1 < source.len
                && source[cursor.offset] == '*' && source[cursor.offset + 1] == '/' {
                nesting -= 1;
                cursor.offset += 2;
                cursor.column += 2;
            } else if source[cursor.offset] == '\r' || source[cursor.offset] == '\n' {
                cursor.offset = newline(source, cursor.offset);
                cursor.line += 1;
                cursor.column = 1;
            } else {
                cursor.offset += 1;
                cursor.column += 1;
            }
        }
        return COMMENT;
    }

    return 0;
}

fn scan_raw_string(source: const u8[:], cursor: Position&) -> i32 {
    if cursor.offset + 2 < source.len && source[cursor.offset] == '"'
        && source[cursor.offset + 1] == '"' && source[cursor.offset + 2] == '"' {
        cursor.offset += 3;
        cursor.column += 3;
        while cursor.offset < source.len {
            if cursor.offset + 2 < source.len && source[cursor.offset] == '"'
                && source[cursor.offset + 1] == '"' && source[cursor.offset + 2] == '"' {
                cursor.offset += 3;
                cursor.column += 3;
                break;
            }
            if source[cursor.offset] == '\r' || source[cursor.offset] == '\n' {
                cursor.offset = newline(source, cursor.offset);
                cursor.line += 1;
                cursor.column = 1;
            } else {
                cursor.offset += 1;
                cursor.column += 1;
            }
        }
        return STRING;
    }

    return 0;
}

fn scan_quoted(source: const u8[:], cursor: Position&) -> i32 {
    let byte = source[cursor.offset];
    if byte == '"' || byte == '\'' {
        let quote = byte;
        cursor.offset += 1;
        cursor.column += 1;
        while cursor.offset < source.len {
            if source[cursor.offset] == '\\' {
                cursor.offset += 1;
                cursor.column += 1;
                if cursor.offset < source.len {
                    if source[cursor.offset] == '\r' || source[cursor.offset] == '\n' {
                        cursor.offset = newline(source, cursor.offset);
                        cursor.line += 1;
                        cursor.column = 1;
                    } else {
                        cursor.offset += 1;
                        cursor.column += 1;
                    }
                }
                continue;
            }
            if source[cursor.offset] == quote {
                cursor.offset += 1;
                cursor.column += 1;
                break;
            }
            if source[cursor.offset] == '\r' || source[cursor.offset] == '\n' {
                break;
            }
            cursor.offset += 1;
            cursor.column += 1;
        }
        let kind = if quote == '"' {
            STRING
        } else {
            CHARACTER
        };
        return kind;
    }

    return 0;
}

fn scan_atom(source: const u8[:], cursor: Position&) -> i32 {
    let start = cursor.offset;
    let byte = source[start];
    if identifier_start(byte) {
        cursor.offset += 1;
        while cursor.offset < source.len && identifier_byte(source[cursor.offset]) {
            cursor.offset += 1;
        }
        cursor.column += cursor.offset - start;
        return IDENT;
    }
    if byte >= '0' && byte <= '9' {
        cursor.offset = scan_number(source, start);
        cursor.column += cursor.offset - start;
        return NUMBER;
    }
    let op = operator_at(source, start);
    let length = if op.len > 0 {
        op.len
    } else {
        1
    };
    cursor.offset += length;
    cursor.column += length;
    return if op.len > 0 {
        OPERATOR
    } else {
        PUNCTUATION
    };
}
