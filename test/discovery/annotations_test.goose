// Metadata requires exact spelling, supported escapes, and contiguous attachment to a test.
namespace annotations_test;

import goosetest.src.discovery.manifest;
import goosetest.src.discovery.model;
import goosetest.test_support.syntax;

import std;

fn test_bad_annotations() {
    check("// @Tag(\"x\")", discovery::SyntaxIssue.UnknownAnnotation);
    check("// @RepeatedTest(2)", discovery::SyntaxIssue.UnknownAnnotation);
    check("// @Unknown(\"x\")", discovery::SyntaxIssue.UnknownAnnotation);
    check("// @Disabled(\"\")", discovery::SyntaxIssue.EmptyDisabled);
    check("// @Disabled()", discovery::SyntaxIssue.AnnotationArgument);
    check("// @DisplayName(123)", discovery::SyntaxIssue.AnnotationArgument);
    check("// @DisplayName(\"a\", \"b\")", discovery::SyntaxIssue.AnnotationArgument);
    check("// @DisplayName(\"a\") trailing", discovery::SyntaxIssue.AnnotationArgument);
    check("// @DisplayName(\"bad\\q\")", discovery::SyntaxIssue.MalformedAnnotation);
    check("// @DisplayName(\"\"\"raw\"\"\")", discovery::SyntaxIssue.AnnotationArgument);
    check("// @Disabled(\"a\")\n// @Disabled(\"b\")", discovery::SyntaxIssue.DuplicateAnnotation);
}

fn test_orphans() {
    let misplaced = str("namespace x;\nfn test_x(\n// @Disabled(\"why\")\n",
        "t: goosetest::Test&) {}");
    syntax_support::expect_error(misplaced, discovery::SyntaxIssue.OrphanAnnotation, 3);
    let body_gap = str("namespace x;\nfn test_x(t: goosetest::Test&)\n",
        "// @Unknown(\"why\")\n{}");
    syntax_support::expect_error(body_gap, discovery::SyntaxIssue.OrphanAnnotation, 3);
    check("// @Disabled(\"x\")\n", discovery::SyntaxIssue.OrphanAnnotation);
    check("// @Disabled(\"x\")\n/* doc */", discovery::SyntaxIssue.OrphanAnnotation);
    check("// @Disabled(\"x\")\nfn helper() {}", discovery::SyntaxIssue.OrphanAnnotation);
    syntax_support::expect_error("namespace x; // @Disabled(\"x\")\nfn test_x(t: goosetest::Test&) {}",
        discovery::SyntaxIssue.AnnotationLine, 1);
    syntax_support::expect_error("namespace x;\n// @Disabled(\"x\")", discovery::SyntaxIssue.OrphanAnnotation, 2);
}

fn test_metadata_escapes() {
    syntax_support::with_manifest() {
        manifest =>
        let source = "namespace x;\n// Mention @Unknown in prose.\n// @DisplayName(\"\\n\\r\\t\\0\\\\\\\"\\'\\x41\")\n// @Disabled(\"why\")\nfn test_x(t: goosetest::Test&) {}";
        syntax_support::parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 0);
        let entry = manifest.cases[0];
        assert(discovery::manifest_text(manifest, entry.display_name) == "\n\r\t\0\\\"'A");
        assert(discovery::manifest_text(manifest, entry.disabled_reason) == "why");
        assert(entry.location.line == 5);
    }
}

fn check(annotation: u8[:], issue: discovery::SyntaxIssue) {
    let source = str("namespace x;\n", annotation, "\nfn test_x(t: goosetest::Test&) {}");
    syntax_support::expect_error(source, issue);
}
