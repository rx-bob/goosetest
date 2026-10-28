// Manifest metadata is owned independently of source/lexer lifetimes; errors retain path and location.
namespace discovery;

import std;

import src.discovery.model;
import src.discovery.syntax_errors;

struct Hook {
    present: bool = false,
    uses_context: bool = false,
    uses_fixture: bool = false,
    location: SourceLocation = SourceLocation {
    },
}
struct Suite {
    path: Span,
    namespace_name: Span = Span {
    },
    namespace_location: SourceLocation = SourceLocation {
    },
    has_namespace: bool = false,
    has_fixture: bool = false,
    fixture_location: SourceLocation = SourceLocation {
    },
    before_each: Hook = Hook {
    },
    after_each: Hook = Hook {
    },
    before_all: Hook = Hook {
    },
    after_all: Hook = Hook {
    },
    first_case: i64,
    case_count: i64 = 0,
    source_file: i64 = -1,
    kind: RootKind,
}
struct Case {
    suite_index: i64,
    name: Span,
    identity: Span,
    location: SourceLocation,
    uses_fixture: bool,
    has_display: bool = false,
    display_name: Span = Span {
    },
    disabled: bool = false,
    disabled_reason: Span = Span {
    },
}
struct Metadata {
    has_display: bool = false,
    display_name: Span = Span {
    },
    disabled: bool = false,
    disabled_reason: Span = Span {
    },
    location: SourceLocation = SourceLocation {
    },
    end_line: i64 = 0,
}
struct Manifest {
    suites: Suite[>..]&,
    cases: Case[>..]&,
    text: u8[>..]&,
    error_path: u8[>..]&,
    target_name: Span = Span {
    },
    limits: SyntaxLimits,
    error: ScanError = ScanError {
    },
    scanned_bytes: i64 = 0,
    complete: bool = false,
}

fn set_target_name(manifest: Manifest&, name: u8[:]) {
    if name.len == 0 {
        return;
    }
    manifest.target_name = own_text(manifest, name, "", SourceLocation {
        });
}

fn new_manifest(
    suites: Suite[>..]&, cases: Case[>..]&, text: u8[>..]&, error_path: u8[>..]&, limits: SyntaxLimits = SyntaxLimits {
    }
) -> Manifest {
    assert(suites.len == 0);
    assert(cases.len == 0);
    assert(text.len == 0);
    assert(error_path.len == 0);
    var manifest = Manifest {
        suites: suites,
        cases: cases,
        text: text,
        error_path: error_path,
        limits: limits,
        ..
    };
    let values: i64[7] = [limits.max_file_bytes, limits.max_total_bytes, limits.max_tokens, limits.max_nesting,
        limits.max_suites, limits.max_cases, limits.max_text_bytes];
    for value in values {
        if value < 0 {
            syntax_fail(manifest, "", SourceLocation {
                }, SyntaxIssue.InvalidSyntaxLimits);
        }
    }
    return manifest;
}

fn syntax_fail(manifest: Manifest&, path: u8[:], location: SourceLocation, issue: SyntaxIssue) {
    if manifest.error.issue != SyntaxIssue.None {
        return;
    }
    manifest.error = ScanError {
        issue: issue,
        location: location
    };
    manifest.error_path.append(path);
    manifest.complete = false;
}

fn manifest_text(manifest: Manifest&, span: Span) -> const u8[:] {
    return manifest.text[span.offset..span.offset + span.length];
}

fn own_text(manifest: Manifest&, value: u8[:], path: u8[:], location: SourceLocation) -> Span {
    if manifest.error.issue != SyntaxIssue.None {
        return Span {
        };
    }
    if value.len > manifest.limits.max_text_bytes - manifest.text.len {
        syntax_fail(manifest, path, location, SyntaxIssue.TextBytes);
        return Span {
        };
    }
    let span = Span {
        offset: manifest.text.len,
        length: value.len
    };
    manifest.text.append(value);
    return span;
}

fn manifest_status(manifest: Manifest&) -> i32 {
    if manifest.complete && manifest.error.issue == SyntaxIssue.None {
        return 0;
    }
    return 2;
}

fn manifest_error_text(manifest: Manifest&) -> u8[>..] {
    return str(manifest.error_path, ":", manifest.error.location.line, ":", manifest.error.location.column,
        ": ", issue_message(manifest.error.issue));
}

fn has_metadata(metadata: Metadata) -> bool {
    return metadata.has_display || metadata.disabled;
}
