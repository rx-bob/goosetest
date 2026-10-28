// Signature rejection is independent from compiler type checking of test bodies.
namespace signatures_test;

import std;

import goosetest;
import src.discovery.manifest;
import src.discovery.model;
import test_support.syntax;

fn test_bad_parameters(outer: goosetest::Test&) {
    check("fn test_x() {}", discovery::SyntaxIssue.TestSignature);
    check("fn test_x(f: Fixture&) {}", discovery::SyntaxIssue.TestSignature);
    check("fn test_x(t: Test&) {}", discovery::SyntaxIssue.ParameterType);
    check("fn test_x(t: goosetest::Test) {}", discovery::SyntaxIssue.UnexpectedToken);
    check("fn test_x(t: const goosetest::Test&) {}", discovery::SyntaxIssue.ParameterType);
    check("fn test_x(t: goosetest::Test&, f: other::Fixture&) {}", discovery::SyntaxIssue.ParameterType);
    check("fn test_x(t: goosetest::Test&, f: Fixture&, x: i64) {}", discovery::SyntaxIssue.ParameterCount);
    check("fn test_x(t: goosetest::Test& = value) {}", discovery::SyntaxIssue.UnexpectedToken);
    check("fn test_x(t: goosetest::Test&) -> bool {}", discovery::SyntaxIssue.FunctionBody);
    check("fn test_x(t: goosetest::Test&);", discovery::SyntaxIssue.FunctionBody);
}

fn test_unsupported_modifiers(outer: goosetest::Test&) {
    check("fn test_x<T>(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("recursive fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("thread_fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("extern fn test_x(t: goosetest::Test&);", discovery::SyntaxIssue.FunctionModifiers);
    check("extern \"foreign\" fn test_x(t: goosetest::Test&);", discovery::SyntaxIssue.FunctionModifiers);
    check("export fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("simd fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("checkfree fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("inline inline fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("fn ::test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
    check("fn nested::test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.FunctionModifiers);
}

fn test_hook_signatures(outer: goosetest::Test&) {
    check("fn before_all(f: Fixture&) {}", discovery::SyntaxIssue.HookSignature);
    check("fn after_all(t: goosetest::Test&, f: Fixture&) {}", discovery::SyntaxIssue.HookSignature);
    check("fn before_each() {}", discovery::SyntaxIssue.HookSignature);
    check("fn after_each(t: goosetest::Test&) {}", discovery::SyntaxIssue.HookSignature);
    check("fn before_each(f: Fixture&) {} fn before_each(t: goosetest::Test&, f: Fixture&) {}",
        discovery::SyntaxIssue.DuplicateHook);
}

fn check(declaration: u8[:], issue: discovery::SyntaxIssue) {
    syntax_support::expect_error(str("namespace sample;\nstruct Fixture {}\n", declaration), issue, 3);
}
