// Focused function-signature grammar; compiler still owns body/type checking.
namespace discovery;

import src.discovery.annotations;
import src.discovery.lexer;
import src.discovery.manifest;
import src.discovery.model;
import src.discovery.paths;

struct Parser {
    manifest: Manifest&,
    source: const u8[:],
    tokens: const Token[:],
    suite_index: i64,
    at: i64 = 0,
    prefix_bad: bool = false,
    inline_count: i64 = 0,
    prefix_started: bool = false,
    seen_declaration: bool = false,
    metadata: Metadata = Metadata {
    },
}
struct Signature {
    count: i64 = 0,
    first: i32 = 0,
    second: i32 = 0
}

fn parser_path(parser: Parser&) -> const u8[:] {
    return manifest_text(parser.manifest, parser.manifest.suites[parser.suite_index].path);
}

fn here(parser: Parser&) -> SourceLocation {
    if parser.at < parser.tokens.len {
        return parser.tokens[parser.at].location;
    }
    if parser.tokens.len > 0 {
        return parser.tokens[parser.tokens.len - 1].location;
    }
    return SourceLocation {
    };
}

fn parse_error(parser: Parser&, issue: SyntaxIssue) {
    syntax_fail(parser.manifest, parser_path(parser), here(parser), issue);
}

fn text_at(parser: Parser&) -> const u8[:] {
    if parser.at >= parser.tokens.len {
        return "";
    }
    return token_text(parser.source, parser.tokens[parser.at]);
}

fn is_comment(token: Token) -> bool {
    return token.kind == TokenKind.LineComment || token.kind == TokenKind.BlockComment;
}

fn skip_comments(parser: Parser&) {
    while parser.at < parser.tokens.len && is_comment(parser.tokens[parser.at]) {
        let token = parser.tokens[parser.at];
        if token.kind == TokenKind.LineComment {
            let body = comment_body(parser.source, token);
            if body.len > 0 && body[0] == '@' {
                parse_error(parser, SyntaxIssue.OrphanAnnotation);
                return;
            }
        }
        parser.at += 1;
    }
}

fn take(parser: Parser&, text: u8[:]) -> bool {
    skip_comments(parser);
    if text_at(parser) == text {
        parser.at += 1;
        return true;
    }
    parse_error(parser, SyntaxIssue.UnexpectedToken);
    return false;
}

fn identifier(parser: Parser&) -> Token {
    skip_comments(parser);
    if parser.at < parser.tokens.len {
        let token = parser.tokens[parser.at];
        if token.kind == TokenKind.Identifier && import_segment(text_at(parser)) {
            parser.at += 1;
            return token;
        }
    }
    parse_error(parser, SyntaxIssue.Identifier);
    return Token {
        kind: TokenKind.Identifier,
        span: Span {
        },
        location: here(parser),
        end_line: here(parser).line,
        ..
    };
}

// 1 is Test&, 2 is local Fixture&; parameter names never affect identity.
fn parameter(parser: Parser&) -> i32 {
    identifier(parser);
    if !take(parser, ":") {
        return 0;
    }
    skip_comments(parser);
    var kind: i32 = 0;
    if text_at(parser) == "goosetest" {
        parser.at += 1;
        if !take(parser, "::") {
            return 0;
        }
        if !take(parser, "Test") {
            return 0;
        }
        kind = 1;
    } else if text_at(parser) == "Fixture" {
        parser.at += 1;
        kind = 2;
    }
    else {
        parse_error(parser, SyntaxIssue.ParameterType);
        return 0;
    }
    if !take(parser, "&") {
        return 0;
    }
    return kind;
}

fn parse_signature(parser: Parser&) -> Signature {
    var signature = Signature {
    };
    if !take(parser, "(") {
        return signature;
    }
    skip_comments(parser);
    while parser.at < parser.tokens.len && text_at(parser) != ")" && parser.manifest.error.issue == SyntaxIssue.None {
        if signature.count == 2 {
            parse_error(parser, SyntaxIssue.ParameterCount);
            return signature;
        }
        let kind = parameter(parser);
        if signature.count == 0 {
            signature.first = kind;
        } else {
            signature.second = kind;
        }
        signature.count += 1;
        skip_comments(parser);
        if text_at(parser) == ")" {
            break;
        }
        if !take(parser, ",") {
            return signature;
        }
        skip_comments(parser);
    }
    take(parser, ")");
    return signature;
}

fn test_signature(signature: Signature) -> bool {
    return signature.first == 1 && (signature.count == 1 || (signature.count == 2 && signature.second == 2));
}

fn hook_signature(name: u8[:], signature: Signature) -> bool {
    if name == "before_all" || name == "after_all" {
        return signature.count == 0 || (signature.count == 1 && signature.first == 1);
    }
    return (signature.count == 1 && signature.first == 2)
        || (signature.count == 2 && signature.first == 1 && signature.second == 2);
}

fn hook_name(name: u8[:]) -> bool {
    return name == "before_each" || name == "after_each" || name == "before_all" || name == "after_all";
}

fn test_name(name: u8[:]) -> bool {
    return name.len >= 5 && name[..5] == "test_";
}

fn skip_group(parser: Parser&) {
    let token = parser.tokens[parser.at];
    if token.mate <= parser.at {
        parse_error(parser, SyntaxIssue.OpeningDelimiter);
        return;
    }
    parser.at = token.mate + 1;
}

fn require_body(parser: Parser&) {
    skip_comments(parser);
    if text_at(parser) != "{" {
        parse_error(parser, SyntaxIssue.FunctionBody);
        return;
    }
    skip_group(parser);
}
