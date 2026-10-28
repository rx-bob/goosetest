// Only standalone immediately attached line-comment metadata affects discovered tests.
namespace discovery;

import src.discovery.lexer;
import src.discovery.manifest;
import src.discovery.model;

fn comment_body(source: u8[:], token: Token) -> const u8[:] {
    let text = token_text(source, token);
    var start: i64 = 2;
    while start < text.len && (text[start] == ' ' || text[start] == '\t') {
        start += 1;
    }
    return text[start..];
}

fn annotation_comment(
    manifest: Manifest&, path: u8[:], source: u8[:], token: Token, metadata: Metadata&
) {
    let body = comment_body(source, token);
    if body.len == 0 || body[0] != '@' {
        return;
    }
    if !token.standalone {
        syntax_fail(manifest, path, token.location, SyntaxIssue.AnnotationLine);
        return;
    }
    var tokens: Token[>..] = [];
    let error = lex(body, tokens, manifest.limits);
    if error.issue != SyntaxIssue.None {
        syntax_fail(manifest, path, token.location, SyntaxIssue.MalformedAnnotation);
        return;
    }
    if tokens.len < 2 {
        syntax_fail(manifest, path, token.location, SyntaxIssue.MalformedAnnotation);
        return;
    }
    let name = token_text(body, tokens[1]);
    if name != "DisplayName" && name != "Disabled" {
        syntax_fail(manifest, path, token.location, SyntaxIssue.UnknownAnnotation);
        return;
    }
    if tokens.len != 5 {
        syntax_fail(manifest, path, token.location, SyntaxIssue.AnnotationArgument);
        return;
    }
    if token_text(body, tokens[2]) != "(" || token_text(body, tokens[4]) != ")"
        || tokens[3].kind != TokenKind.String || tokens[3].raw {
        syntax_fail(manifest, path, token.location, SyntaxIssue.AnnotationArgument);
        return;
    }
    let value = decode_string(token_text(body, tokens[3]));
    attach_value(manifest, path, token.location, name, value, metadata);
}

fn attach_value(
    manifest: Manifest&, path: u8[:], location: SourceLocation, name: u8[:], value: u8[:], metadata: Metadata&
) {
    if (name == "DisplayName" && metadata.has_display) || (name == "Disabled" && metadata.disabled) {
        syntax_fail(manifest, path, location, SyntaxIssue.DuplicateAnnotation);
        return;
    }
    if name == "Disabled" && value.len == 0 {
        syntax_fail(manifest, path, location, SyntaxIssue.EmptyDisabled);
        return;
    }
    if !has_metadata(metadata) {
        metadata.location = location;
    }
    let span = own_text(manifest, value, path, location);
    if name == "DisplayName" {
        metadata.has_display = true;
        metadata.display_name = span;
    } else {
        metadata.disabled = true;
        metadata.disabled_reason = span;
    }
}

// Lexer validated delimiters and escapes; decoded bytes are copied into manifest storage.
fn decode_string(quoted: u8[:]) -> u8[>..] {
    var result: u8[>..] = [];
    var at: i64 = 1;
    while at < quoted.len - 1 {
        var byte = quoted[at];
        at += 1;
        if byte == '\\' {
            byte = quoted[at];
            at += 1;
            if byte == 'x' {
                byte = (hex_value(quoted[at]) * 16 + hex_value(quoted[at + 1]))as u8;
                at += 2;
            } else if byte == 'n' {
                byte = '\n';
            } else if byte == 'r' {
                byte = '\r';
            } else if byte == 't' {
                byte = '\t';
            } else if byte == '0' {
                byte = 0;
            }
        }
        result.push(byte);
    }
    return result;
}
