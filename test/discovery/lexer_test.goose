// Literal/comment decoys and delimiter/byte budgets are checked without the declaration parser.
namespace lexer_test;

import goosetest;
import src.discovery.lexer;
import src.discovery.model;

fn test_locations(outer: goosetest::Test&) {
    var tokens: discovery::Token[>..] = [];
    let source = "\xEF\xBB\xBF// header\r\nnamespace sample;\r\n  fn test_x() {}\n";
    let error = discovery::lex(source, tokens);
    assert(error.issue == discovery::SyntaxIssue.None);
    assert(tokens[1].location.line == 2);
    assert(tokens[1].location.column == 1);
    assert(tokens[4].location.line == 3);
    assert(tokens[4].location.column == 3);
    assert(discovery::token_text(source, tokens[4]) == "fn");
}

fn test_groups(outer: goosetest::Test&) {
    var tokens: discovery::Token[>..] = [];
    let error = discovery::lex("([{ }])", tokens, discovery::SyntaxLimits {
            max_nesting: 3,
            ..
        });
    assert(error.issue == discovery::SyntaxIssue.None);
    assert(tokens.len == 6);
    assert(tokens[0].mate == 5);
    assert(tokens[1].mate == 4);
    assert(tokens[2].mate == 3);
    assert(tokens[5].mate == 0);
    expect_error("([{ }])", discovery::SyntaxIssue.Nesting, discovery::SyntaxLimits {
            max_nesting: 2,
            ..
        });
    expect_error("(/* nested /* inner */ */)", discovery::SyntaxIssue.CommentNesting,
        discovery::SyntaxLimits {
            max_nesting: 2,
            ..
        });
}

fn test_lexical_errors(outer: goosetest::Test&) {
    expect_error("\"unterminated", discovery::SyntaxIssue.UnterminatedQuote);
    expect_error("\"\"\"unterminated", discovery::SyntaxIssue.UnterminatedRaw);
    expect_error("/* unterminated", discovery::SyntaxIssue.UnterminatedComment);
    expect_error("\"bad\\q\"", discovery::SyntaxIssue.UnknownEscape);
    expect_error("\"bad\\x0Z\"", discovery::SyntaxIssue.HexEscape);
    expect_error("\"actual\nnewline\"", discovery::SyntaxIssue.QuotedNewline);
    expect_error("'ab'", discovery::SyntaxIssue.CharacterWidth);
    expect_error("'", discovery::SyntaxIssue.UnterminatedQuote);
    expect_error("}", discovery::SyntaxIssue.UnmatchedDelimiter);
    expect_error("([)]", discovery::SyntaxIssue.MismatchedDelimiter);
    expect_error("{", discovery::SyntaxIssue.UnclosedDelimiter);
}

fn test_literal_decoys(outer: goosetest::Test&) {
    var tokens: discovery::Token[>..] = [];
    let source = "\"fn test_string() {}\" '\\'' '\\x7D' /* outer /* test_fake */ done */ // fn test_line\n";
    let error = discovery::lex(source, tokens);
    assert(error.issue == discovery::SyntaxIssue.None);
    assert(tokens.len == 5);
    assert(tokens[0].kind == discovery::TokenKind.String);
    assert(tokens[1].kind == discovery::TokenKind.Character);
    assert(tokens[3].kind == discovery::TokenKind.BlockComment);
    assert(tokens[4].kind == discovery::TokenKind.LineComment);
}

fn test_lexer_limits(outer: goosetest::Test&) {
    var tokens: discovery::Token[>..] = [];
    let limits = discovery::SyntaxLimits {
        max_tokens: 1,
        max_file_bytes: 3,
        max_nesting: 0,
        ..
    };
    assert(discovery::lex("abc", tokens, limits).issue == discovery::SyntaxIssue.None);
    expect_error("abcd", discovery::SyntaxIssue.FileBytes, limits);
    expect_error("a b", discovery::SyntaxIssue.Tokens, limits);
    expect_error("()", discovery::SyntaxIssue.Nesting, limits);
    var empty: discovery::Token[>..] = [];
    assert(discovery::lex("", empty, discovery::SyntaxLimits {
            max_tokens: 0,
            ..
        }).issue == discovery::SyntaxIssue.None);
}

fn expect_error(
    source: u8[:], issue: discovery::SyntaxIssue, limits: discovery::SyntaxLimits = discovery::SyntaxLimits {
    }) {
    var tokens: discovery::Token[>..] = [];
    let error = discovery::lex(source, tokens, limits);
    assert(error.issue == issue);
    assert(error.location.line == 1);
    assert(tokens.len <= limits.max_tokens);
}
