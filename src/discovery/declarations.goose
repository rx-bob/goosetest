// Top-level declaration discovery skips lexical groups; it never searches source lines for fn text.
namespace discovery;

import std;

import src.discovery.annotations;
import src.discovery.lexer;
import src.discovery.manifest;
import src.discovery.model;
import src.discovery.signatures;

fn parse_file(
    manifest: Manifest&, path: u8[:], source: u8[:], kind: RootKind, source_file: i64 = -1
) {
    assert(!manifest.complete);
    if manifest.error.issue != SyntaxIssue.None {
        return;
    }
    if manifest.suites.len >= manifest.limits.max_suites {
        syntax_fail(manifest, path, SourceLocation {
            }, SyntaxIssue.Suites);
        return;
    }
    if source.len > manifest.limits.max_total_bytes - manifest.scanned_bytes {
        syntax_fail(manifest, path, SourceLocation {
            }, SyntaxIssue.TotalBytes);
        return;
    }
    manifest.scanned_bytes += source.len;
    var tokens: Token[>..] = [];
    let error = lex(source, tokens, manifest.limits);
    if error.issue != SyntaxIssue.None {
        syntax_fail(manifest, path, error.location, error.issue);
        return;
    }
    let stored = own_text(manifest, path, path, SourceLocation {
        });
    if manifest.error.issue != SyntaxIssue.None {
        return;
    }
    let index = manifest.suites.len;
    manifest.suites.push(Suite {
            path: stored,
            first_case: manifest.cases.len,
            source_file: source_file,
            kind: kind,
            ..
        });
    var parser = Parser {
        manifest: manifest,
        source: source,
        tokens: tokens,
        suite_index: index,
        ..
    };
    parse_top_level(parser);
    validate_suite(parser);
}

fn parse_top_level(parser: Parser&) {
    while parser.at < parser.tokens.len && parser.manifest.error.issue == SyntaxIssue.None {
        let before = parser.at;
        let token = parser.tokens[parser.at];
        if is_comment(token) {
            top_comment(parser);
        } else {
            if !parser.prefix_started && has_metadata(parser.metadata)
                && token.location.line > parser.metadata.end_line + 1 {
                parse_error(parser, SyntaxIssue.OrphanAnnotation);
                return;
            }
            top_declaration(parser);
        }
        assert(parser.at > before || parser.manifest.error.issue != SyntaxIssue.None);
    }
    if parser.prefix_started && parser.manifest.error.issue == SyntaxIssue.None {
        parse_error(parser, SyntaxIssue.DanglingModifier);
    }
    if has_metadata(parser.metadata) && parser.manifest.error.issue == SyntaxIssue.None {
        syntax_fail(parser.manifest, parser_path(parser), parser.metadata.location, SyntaxIssue.OrphanAnnotation);
    }
}

fn top_comment(parser: Parser&) {
    let token = parser.tokens[parser.at];
    if has_metadata(parser.metadata) && (token.location.line > parser.metadata.end_line + 1
        || token.kind == TokenKind.BlockComment) {
        parse_error(parser, SyntaxIssue.OrphanAnnotation);
        return;
    }
    if token.kind == TokenKind.LineComment {
        let body = comment_body(parser.source, token);
        if parser.prefix_started && body.len > 0 && body[0] == '@' {
            parse_error(parser, SyntaxIssue.AnnotationModifiers);
            return;
        }
        annotation_comment(parser.manifest, parser_path(parser), parser.source, token, parser.metadata);
        if has_metadata(parser.metadata) {
            parser.metadata.end_line = token.end_line;
        }
    }
    parser.at += 1;
}

fn top_declaration(parser: Parser&) {
    let text = text_at(parser);
    if text == "namespace" && parser.seen_declaration {
        parse_error(parser, SyntaxIssue.NamespaceOrder);
        return;
    }
    if text != "namespace" && text != "import" {
        parser.seen_declaration = true;
    }
    if text == "inline" {
        parser.inline_count += 1;
        parser.prefix_started = true;
        parser.at += 1;
        return;
    }
    if text == "recursive" || text == "extern" || text == "export" || text == "simd" || text == "checkfree" {
        parser.prefix_bad = true;
        parser.prefix_started = true;
        parser.at += 1;
        return;
    }
    if parser.prefix_bad && parser.tokens[parser.at].kind == TokenKind.String {
        parser.at += 1;
        return;
    }
    if text == "fn" || text == "thread_fn" {
        if text == "thread_fn" {
            parser.prefix_bad = true;
        }
        parse_function(parser);
        reset_prefix(parser);
        return;
    }
    if has_metadata(parser.metadata) {
        parse_error(parser, SyntaxIssue.OrphanAnnotation);
        return;
    }
    if text == "namespace" {
        parse_namespace(parser);
    } else if text == "struct" {
        parse_struct(parser);
    } else {
        skip_declaration(parser);
    }
    reset_prefix(parser);
}

fn reset_prefix(parser: Parser&) {
    parser.prefix_bad = false;
    parser.prefix_started = false;
    parser.inline_count = 0;
}

fn parse_namespace(parser: Parser&) {
    let location = here(parser);
    parser.at += 1;
    let name = identifier(parser);
    if !take(parser, ";") {
        return;
    }
    let suite .= parser.manifest.suites[parser.suite_index];
    if suite.has_namespace {
        parse_error(parser, SyntaxIssue.DuplicateNamespace);
        return;
    }
    suite.namespace_name = own_text(parser.manifest, token_text(parser.source, name), parser_path(parser), location);
    suite.namespace_location = location;
    suite.has_namespace = true;
}

fn parse_struct(parser: Parser&) {
    let location = here(parser);
    parser.at += 1;
    let name = identifier(parser);
    if token_text(parser.source, name) != "Fixture" {
        skip_declaration(parser);
        return;
    }
    let suite .= parser.manifest.suites[parser.suite_index];
    if suite.has_fixture {
        parse_error(parser, SyntaxIssue.DuplicateFixture);
        return;
    }
    suite.has_fixture = true;
    suite.fixture_location = location;
    skip_comments(parser);
    if text_at(parser) != "{" {
        parse_error(parser, SyntaxIssue.FixtureShape);
        return;
    }
    skip_group(parser);
}

fn parse_function(parser: Parser&) {
    let location = here(parser);
    parser.at += 1;
    skip_comments(parser);
    var qualified = false;
    if text_at(parser) == "::" {
        qualified = true;
        parser.at += 1;
    }
    var name = identifier(parser);
    skip_comments(parser);
    while text_at(parser) == "::" && parser.manifest.error.issue == SyntaxIssue.None {
        qualified = true;
        parser.at += 1;
        name = identifier(parser);
        skip_comments(parser);
    }
    if parser.manifest.error.issue != SyntaxIssue.None {
        return;
    }
    let spelling = token_text(parser.source, name);
    let is_test = test_name(spelling);
    if !is_test && !hook_name(spelling) {
        if has_metadata(parser.metadata) {
            parse_error(parser, SyntaxIssue.OrphanAnnotation);
            return;
        }
        if text_at(parser) != "(" && text_at(parser) != "<" {
            parse_error(parser, SyntaxIssue.ParameterList);
            return;
        }
        skip_declaration(parser);
        return;
    }
    if qualified || parser.prefix_bad || parser.inline_count > 1 || text_at(parser) == "<" {
        syntax_fail(parser.manifest, parser_path(parser), location, SyntaxIssue.FunctionModifiers);
        return;
    }
    let signature = parse_signature(parser);
    if parser.manifest.error.issue != SyntaxIssue.None {
        return;
    }
    if is_test && !test_signature(signature) {
        parse_error(parser, SyntaxIssue.TestSignature);
        return;
    }
    if !is_test && !hook_signature(spelling, signature) {
        parse_error(parser, SyntaxIssue.HookSignature);
        return;
    }
    require_body(parser);
    if parser.manifest.error.issue != SyntaxIssue.None {
        return;
    }
    if is_test {
        append_case(parser, spelling, location, signature.count == 2);
    } else {
        append_hook(parser, spelling, location, signature);
    }
}

fn append_case(parser: Parser&, name: u8[:], location: SourceLocation, fixture: bool) {
    let manifest .= parser.manifest;
    let suite .= manifest.suites[parser.suite_index];
    if !suite.has_namespace {
        parse_error(parser, SyntaxIssue.NamespaceOrder);
        return;
    }
    if manifest.cases.len >= manifest.limits.max_cases {
        parse_error(parser, SyntaxIssue.Cases);
        return;
    }
    let path = parser_path(parser);
    let target_name = manifest_text(manifest, manifest.target_name);
    let id = if target_name.len > 0 {
        str(target_name, "::", path, "::", manifest_text(manifest, suite.namespace_name), "::", name)
    } else {
        str(path, "::", manifest_text(manifest, suite.namespace_name), "::", name)
    };
    let stored_name = own_text(manifest, name, path, location);
    let stored_id = own_text(manifest, id, path, location);
    if manifest.error.issue != SyntaxIssue.None {
        return;
    }
    manifest.cases.push(Case {
            suite_index: parser.suite_index,
            name: stored_name,
            identity: stored_id,
            location: location,
            uses_fixture: fixture,
            has_display: parser.metadata.has_display,
            display_name: parser.metadata.display_name,
            disabled: parser.metadata.disabled,
            disabled_reason: parser.metadata.disabled_reason,
        });
    suite.case_count += 1;
    parser.metadata = Metadata {
    };
}

fn append_hook(parser: Parser&, name: u8[:], location: SourceLocation, signature: Signature) {
    if has_metadata(parser.metadata) {
        parse_error(parser, SyntaxIssue.OrphanAnnotation);
        return;
    }
    let hook = Hook {
        present: true,
        uses_context: signature.first == 1,
        uses_fixture: signature.first == 2 || signature.second == 2,
        location: location,
    };
    let suite .= parser.manifest.suites[parser.suite_index];
    var duplicate = false;
    if name == "before_each" {
        duplicate = suite.before_each.present;
        suite.before_each = hook;
    } else if name == "after_each" {
        duplicate = suite.after_each.present;
        suite.after_each = hook;
    } else if name == "before_all" {
        duplicate = suite.before_all.present;
        suite.before_all = hook;
    } else {
        duplicate = suite.after_all.present;
        suite.after_all = hook;
    }
    if duplicate {
        syntax_fail(parser.manifest, parser_path(parser), location, SyntaxIssue.DuplicateHook);
    }
}

fn skip_declaration(parser: Parser&) {
    while parser.at < parser.tokens.len && parser.manifest.error.issue == SyntaxIssue.None {
        let text = text_at(parser);
        if text == ";" {
            parser.at += 1;
            return;
        }
        if text == "{" {
            skip_group(parser);
            return;
        }
        if text == "(" || text == "[" {
            skip_group(parser);
        } else {
            parser.at += 1;
        }
    }
}

fn validate_suite(parser: Parser&) {
    if parser.manifest.error.issue != SyntaxIssue.None {
        return;
    }
    let suite = parser.manifest.suites[parser.suite_index];
    if !suite.has_namespace {
        parse_error(parser, SyntaxIssue.MissingNamespace);
        return;
    }
    if suite.has_fixture {
        return;
    }
    if suite.before_each.present || suite.after_each.present {
        parse_error(parser, SyntaxIssue.MissingFixture);
        return;
    }
    for index in suite.first_case..suite.first_case + suite.case_count {
        let entry = parser.manifest.cases[index];
        if entry.uses_fixture {
            syntax_fail(parser.manifest, parser_path(parser), entry.location, SyntaxIssue.MissingFixture);
            return;
        }
    }
}
