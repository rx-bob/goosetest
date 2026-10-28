// Bounded lexical inventory; matching delimiter indices let discovery skip bodies in constant time.
namespace discovery;

import src.discovery.model;
import src.discovery.paths;

// Comments remain tokens so immediately attached metadata can be validated later.
enum TokenKind {
    Identifier,
    Number,
    String,
    Character,
    LineComment,
    BlockComment,
    Symbol
}
struct Token {
    kind: TokenKind,
    span: Span,
    location: SourceLocation,
    end_line: i64,
    mate: i64 = -1,
    standalone: bool = false,
    raw: bool = false,
}
struct LexState {
    source: const u8[:],
    tokens: Token[>..]&,
    brackets: i64[>..<]&,
    limits: SyntaxLimits,
    at: i64 = 0,
    line: i64 = 1,
    column: i64 = 1,
    line_content: bool = false,
    error: ScanError = ScanError {
    },
}

fn lex(source: u8[:], tokens: Token[>..]&, limits: SyntaxLimits = SyntaxLimits {
    }) -> ScanError {
    assert(tokens.len == 0);
    var brackets: i64[>..<] = [];
    var state = LexState {
        source: source,
        tokens: tokens,
        brackets: brackets,
        limits: limits,
        ..
    };
    if limits.max_file_bytes < 0 || limits.max_tokens < 0 || limits.max_nesting < 0 {
        lex_error(state, SyntaxIssue.InvalidSyntaxLimits, SourceLocation {
            });
    } else if source.len > limits.max_file_bytes {
        lex_error(state, SyntaxIssue.FileBytes, SourceLocation {
            });
    }
    if source.len >= 3 && source[0] == 239 && source[1] == 187 && source[2] == 191 {
        state.at = 3;
    }
    while state.at < source.len && state.error.issue == SyntaxIssue.None {
        let before = state.at;
        lex_next(state);
        assert(state.at > before || state.error.issue != SyntaxIssue.None);
    }
    if state.error.issue == SyntaxIssue.None && brackets.len > 0 {
        let opener = tokens[brackets[brackets.len - 1]];
        lex_error(state, SyntaxIssue.UnclosedDelimiter, opener.location);
    }
    return state.error;
}

fn lex_error(state: LexState&, issue: SyntaxIssue, location: SourceLocation) {
    if state.error.issue == SyntaxIssue.None {
        state.error = ScanError {
            issue: issue,
            location: location
        };
    }
}

fn advance(state: LexState&) {
    let byte = state.source[state.at];
    state.at += 1;
    if byte == '\r' {
        if state.at < state.source.len && state.source[state.at] == '\n' {
            state.at += 1;
        }
    }
    if byte == '\r' || byte == '\n' {
        state.line += 1;
        state.column = 1;
        state.line_content = false;
    } else {
        state.column += 1;
    }
}

fn begins(state: LexState&, text: u8[:]) -> bool {
    return text.len <= state.source.len - state.at && state.source[state.at..state.at + text.len] == text;
}

fn lex_next(state: LexState&) {
    let byte = state.source[state.at];
    if byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n' || byte == 11 || byte == 12 {
        advance(state);
        return;
    }
    let start = state.at;
    let location = SourceLocation {
        line: state.line,
        column: state.column
    };
    let standalone = !state.line_content;
    var kind = TokenKind.Symbol;
    var raw = false;
    if begins(state, "//") {
        kind = TokenKind.LineComment;
        scan_line_comment(state);
    } else if begins(state, "/*") {
        kind = TokenKind.BlockComment;
        scan_block_comment(state, location);
    } else if begins(state, "\"\"\"") {
        kind = TokenKind.String;
        raw = true;
        scan_raw(state, location);
    } else if byte == '"' || byte == '\'' {
        kind = if byte == '"' {
            TokenKind.String
        } else {
            TokenKind.Character
        };
        scan_quoted(state, byte, location);
    } else if identifier_start(byte) {
        kind = TokenKind.Identifier;
        scan_identifier(state);
    } else if byte >= '0' && byte <= '9' {
        kind = TokenKind.Number;
        scan_number(state);
    } else {
        advance(state);
        if byte == ':' && begins(state, ":") {
            advance(state);
        } else if byte == '-' && begins(state, ">") {
            advance(state);
        }
    }
    if state.error.issue != SyntaxIssue.None {
        return;
    }
    emit_token(state, Token {
            kind: kind,
            span: Span {
                offset: start,
                length: state.at - start
            },
            location: location,
            end_line: state.line,
            standalone: standalone,
            raw: raw,
            ..
        });
    state.line_content = true;
}

fn emit_token(state: LexState&, token: Token) {
    if state.tokens.len >= state.limits.max_tokens {
        lex_error(state, SyntaxIssue.Tokens, token.location);
        return;
    }
    let index = state.tokens.len;
    state.tokens.push(token);
    if token.kind != TokenKind.Symbol || token.span.length != 1 {
        return;
    }
    let byte = state.source[token.span.offset];
    if byte == '(' || byte == '[' || byte == '{' {
        if state.brackets.len >= state.limits.max_nesting {
            lex_error(state, SyntaxIssue.Nesting, token.location);
            return;
        }
        state.brackets.push(index);
    } else if byte == ')' || byte == ']' || byte == '}' {
        close_bracket(state, byte, index);
    }
}

fn close_bracket(state: LexState&, byte: u8, index: i64) {
    if state.brackets.len == 0 {
        lex_error(state, SyntaxIssue.UnmatchedDelimiter, state.tokens[index].location);
        return;
    }
    let opener = state.brackets.pop();
    let first = state.source[state.tokens[opener].span.offset];
    let expected = if first == '(' {
        ')'
    } else if first == '[' {
        ']'
    } else {
        '}'
    };
    if byte != expected {
        lex_error(state, SyntaxIssue.MismatchedDelimiter, state.tokens[index].location);
        return;
    }
    state.tokens[opener].mate = index;
    state.tokens[index].mate = opener;
}

fn scan_identifier(state: LexState&) {
    while state.at < state.source.len {
        let byte = state.source[state.at];
        if !identifier_start(byte) && !(byte >= '0' && byte <= '9') {
            return;
        }
        advance(state);
    }
}

fn scan_number(state: LexState&) {
    while state.at < state.source.len {
        let byte = state.source[state.at];
        if !identifier_start(byte) && !(byte >= '0' && byte <= '9') {
            return;
        }
        advance(state);
    }
}

fn scan_line_comment(state: LexState&) {
    while state.at < state.source.len && state.source[state.at] != '\r' && state.source[state.at] != '\n' {
        advance(state);
    }
}

fn scan_block_comment(state: LexState&, location: SourceLocation) {
    var depth = 0;
    while state.at < state.source.len {
        if begins(state, "/*") {
            if depth >= state.limits.max_nesting - state.brackets.len {
                lex_error(state, SyntaxIssue.CommentNesting, location);
                return;
            }
            depth += 1;
            advance(state);
            advance(state);
        } else if begins(state, "*/") {
            depth -= 1;
            advance(state);
            advance(state);
            if depth == 0 {
                return;
            }
        } else {
            advance(state);
        }
    }
    lex_error(state, SyntaxIssue.UnterminatedComment, location);
}

fn scan_raw(state: LexState&, location: SourceLocation) {
    advance(state);
    advance(state);
    advance(state);
    while state.at < state.source.len {
        if begins(state, "\"\"\"") {
            advance(state);
            advance(state);
            advance(state);
            return;
        }
        advance(state);
    }
    lex_error(state, SyntaxIssue.UnterminatedRaw, location);
}

fn hex_value(byte: u8) -> i64 {
    if byte >= '0' && byte <= '9' {
        return byte - '0';
    }
    if byte >= 'a' && byte <= 'f' {
        return (byte - 'a')as i64 + 10;
    }
    if byte >= 'A' && byte <= 'F' {
        return (byte - 'A')as i64 + 10;
    }
    return -1;
}

fn scan_quoted(state: LexState&, quote: u8, location: SourceLocation) {
    advance(state);
    var characters: i64 = 0;
    while state.at < state.source.len {
        let byte = state.source[state.at];
        if byte == quote {
            if quote == '\'' && characters != 1 {
                lex_error(state, SyntaxIssue.CharacterWidth, location);
            }
            advance(state);
            return;
        }
        if byte == '\r' || byte == '\n' {
            lex_error(state, SyntaxIssue.QuotedNewline, location);
            return;
        }
        characters += 1;
        if byte == '\\' {
            scan_escape(state, location);
        } else {
            advance(state);
        }
        if state.error.issue != SyntaxIssue.None {
            return;
        }
    }
    lex_error(state, SyntaxIssue.UnterminatedQuote, location);
}

fn scan_escape(state: LexState&, location: SourceLocation) {
    advance(state);
    if state.at == state.source.len {
        lex_error(state, SyntaxIssue.UnterminatedEscape, location);
        return;
    }
    let byte = state.source[state.at];
    advance(state);
    if byte == 'x' {
        for count in 0..2 {
            if state.at == state.source.len || hex_value(state.source[state.at]) < 0 {
                lex_error(state, SyntaxIssue.HexEscape, location);
                return;
            }
            advance(state);
        }
    } else if byte != 'n' && byte != 'r' && byte != 't' && byte != '0' && byte != '\\' && byte != '"' && byte != '\'' {
        lex_error(state, SyntaxIssue.UnknownEscape, location);
    }
}

fn token_text(source: u8[:], token: Token) -> const u8[:] {
    return source[token.span.offset..token.span.offset + token.span.length];
}
