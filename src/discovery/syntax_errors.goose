// Typed, allocation-independent syntax diagnostics.
namespace discovery;

import src.discovery.model;

fn issue_message(issue: SyntaxIssue) -> const u8[:] {
    if issue == SyntaxIssue.BadTestFilename {
        return "expected named *_test.goose suite; move helpers to test_support/";
    }
    if issue == SyntaxIssue.EmptySuite {
        return "test suite requires at least one valid test declaration";
    }
    if issue == SyntaxIssue.NoCases {
        return "no test cases discovered in test/ or integration/";
    }
    let lexical_message_text = lexical_message(issue);
    if lexical_message_text.len > 0 {
        return lexical_message_text;
    }
    let metadata_message_text = metadata_message(issue);
    if metadata_message_text.len > 0 {
        return metadata_message_text;
    }
    let declaration_message_text = declaration_message(issue);
    if declaration_message_text.len > 0 {
        return declaration_message_text;
    }
    let manifest_message_text = manifest_message(issue);
    if manifest_message_text.len > 0 {
        return manifest_message_text;
    }
    return "";
}

fn lexical_message(issue: SyntaxIssue) -> const u8[:] {
    match issue {
        FileBytes => {
            return "max_file_bytes exceeded";
        },
        Tokens => {
            return "max_tokens exceeded";
        },
        Nesting => {
            return "max_nesting exceeded";
        },
        UnclosedDelimiter => {
            return "unclosed delimiter";
        },
        UnmatchedDelimiter => {
            return "unmatched closing delimiter";
        },
        MismatchedDelimiter => {
            return "mismatched delimiter";
        },
        CommentNesting => {
            return "max_nesting exceeded in comment";
        },
        UnterminatedComment => {
            return "unterminated block comment";
        },
        UnterminatedRaw => {
            return "unterminated raw string";
        },
        CharacterWidth => {
            return "character literal requires one byte";
        },
        QuotedNewline => {
            return "newline in quoted literal";
        },
        UnterminatedQuote => {
            return "unterminated quoted literal";
        },
        UnterminatedEscape => {
            return "unterminated escape";
        },
        HexEscape => {
            return "invalid hexadecimal escape";
        },
        UnknownEscape => {
            return "unsupported escape";
        },
        _ => {
            return "";
        },
    }
}

fn metadata_message(issue: SyntaxIssue) -> const u8[:] {
    match issue {
        AnnotationLine => {
            return "framework annotations must occupy their own line";
        },
        MalformedAnnotation => {
            return "malformed framework annotation";
        },
        UnknownAnnotation => {
            return "unsupported annotation; only @DisplayName and @Disabled are supported";
        },
        AnnotationArgument => {
            return "annotation requires one quoted string argument";
        },
        DuplicateAnnotation => {
            return "duplicate framework annotation";
        },
        EmptyDisabled => {
            return "disabled reason must not be empty";
        },
        AnnotationModifiers => {
            return "annotation must precede the declaration modifiers";
        },
        OrphanAnnotation => {
            return "framework annotation must attach to a test function";
        },
        _ => {
            return "";
        },
    }
}

fn declaration_message(issue: SyntaxIssue) -> const u8[:] {
    match issue {
        UnexpectedToken => {
            return "unexpected token in supported declaration";
        },
        Identifier => {
            return "expected an unqualified identifier";
        },
        ParameterType => {
            return "expected goosetest::Test& or local Fixture&";
        },
        ParameterCount => {
            return "at most two parameters are supported";
        },
        OpeningDelimiter => {
            return "expected opening delimiter";
        },
        FunctionBody => {
            return "test and hook declarations require a body and no return type";
        },
        DanglingModifier => {
            return "declaration modifiers require a function";
        },
        NamespaceOrder => {
            return "namespace must precede declarations";
        },
        DuplicateNamespace => {
            return "only one namespace declaration is allowed per test file";
        },
        DuplicateFixture => {
            return "duplicate Fixture declaration";
        },
        FixtureShape => {
            return "Fixture must be a local non-generic struct";
        },
        ParameterList => {
            return "function declaration requires a parameter list";
        },
        FunctionModifiers => {
            return "unsupported test or hook declaration modifiers";
        },
        TestSignature => {
            return "test requires Test& and optional local Fixture&";
        },
        HookSignature => {
            return "unsupported lifecycle hook signature";
        },
        DuplicateHook => {
            return "duplicate lifecycle hook";
        },
        MissingNamespace => {
            return "test file requires one declared namespace";
        },
        MissingFixture => {
            return "Fixture parameter requires a local struct Fixture";
        },
        _ => {
            return "";
        },
    }
}

fn manifest_message(issue: SyntaxIssue) -> const u8[:] {
    match issue {
        InvalidSyntaxLimits => {
            return "syntax limits must be nonnegative";
        },
        TextBytes => {
            return "max_text_bytes exceeded";
        },
        IncompleteInventory => {
            return "cannot discover from an incomplete inventory";
        },
        DuplicateCase => {
            return "duplicate test identity";
        },
        SuiteCollision => {
            return "duplicate suite namespace";
        },
        Suites => {
            return "max_suites exceeded";
        },
        TotalBytes => {
            return "max_total_bytes exceeded";
        },
        Cases => {
            return "max_cases exceeded";
        },
        _ => {
            return "";
        },
    }
}
