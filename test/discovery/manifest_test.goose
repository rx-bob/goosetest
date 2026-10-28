// Exact syntax budgets cannot silently drop suites, cases, or owned metadata.
namespace manifest_test;

import goosetest;
import src.discovery.catalog;
import src.discovery.declarations;
import src.discovery.manifest;
import src.discovery.model;
import test_support.syntax;

let TWO_CASES = "namespace x; fn test_a(t: goosetest::Test&) {} fn test_b(t: goosetest::Test&) {}";

fn test_case_and_suite_limits(outer: goosetest::Test&) {
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_cases: 2,
            max_suites: 1,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases.len == 2);
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_cases: 1,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(discovery::manifest_status(manifest) == 2);
        assert(manifest.error.issue == discovery::SyntaxIssue.Cases);
        assert(manifest.cases.len == 1);
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_suites: 1,
            ..
        }) {
        manifest =>
        discovery::parse_file(manifest, "a_test.goose", "namespace a;", discovery::RootKind.Unit);
        discovery::parse_file(manifest, "b_test.goose", "namespace b;", discovery::RootKind.Unit);
        discovery::finish_manifest(manifest);
        assert(manifest.error.issue == discovery::SyntaxIssue.Suites);
        assert(manifest.suites.len == 1);
        assert(manifest.error_path == "b_test.goose");
    }
}

fn test_byte_limits(outer: goosetest::Test&) {
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_file_bytes: TWO_CASES.len,
            max_total_bytes: TWO_CASES.len,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.scanned_bytes == TWO_CASES.len);
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_file_bytes: TWO_CASES.len - 1,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(manifest.error.issue == discovery::SyntaxIssue.FileBytes);
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_total_bytes: TWO_CASES.len - 1,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(manifest.error.issue == discovery::SyntaxIssue.TotalBytes);
        assert(manifest.scanned_bytes == 0);
    }
}

fn test_text_limits(outer: goosetest::Test&) {
    var needed: i64 = 0;
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        needed = manifest.text.len;
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_text_bytes: needed,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(discovery::manifest_status(manifest) == 0);
    }
    syntax_support::with_manifest(discovery::SyntaxLimits {
            max_text_bytes: needed - 1,
            ..
        }) {
        manifest =>
        syntax_support::parse(manifest, TWO_CASES);
        assert(discovery::manifest_status(manifest) == 2);
        assert(manifest.error.issue == discovery::SyntaxIssue.TextBytes);
        assert(manifest.text.len < needed);
        assert(manifest.cases.len == 1);
    }
}

fn test_invalid_limits(outer: goosetest::Test&) {
    let limits: discovery::SyntaxLimits[7] = [
        discovery::SyntaxLimits {
            max_file_bytes: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_total_bytes: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_tokens: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_nesting: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_suites: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_cases: -1,
            ..
        },
        discovery::SyntaxLimits {
            max_text_bytes: -1,
            ..
        },
    ];
    for limit in limits {
        syntax_support::with_manifest(limit) {
            manifest =>
            syntax_support::parse(manifest, TWO_CASES);
            assert(manifest.error.issue == discovery::SyntaxIssue.InvalidSyntaxLimits);
            assert(discovery::manifest_status(manifest) == 2);
            assert(manifest.cases.len == 0);
        }
    }
}
