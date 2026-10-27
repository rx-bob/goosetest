import std;
import goosetest;
import src.auth.token;

// ============================================================================
// Mirrored Test: test/auth/token_test.goose  <->  src/auth/token.goose
// Notice: NO `fn main()`, NO boilerplate runner setup! Just pure JUnit-style
// lifecycle hooks (`before_each`, `after_each`) and `test_*` functions.
// ============================================================================
namespace auth_token_test;

struct Fixture {
    admin_header: const u8[:] = "",
    teardown_count: i64 = 0,
}

fn before_each(f: Fixture&) {
    f.admin_header = "Bearer tok_admin";
}

fn after_each(f: Fixture&) {
    f.teardown_count += 1;
}

// @DisplayName("parses valid admin Bearer token into claims")
// @Tag("auth")
fn test_valid_admin_bearer(t: Test&, f: Fixture&) {
    let claims = auth_token::parse_bearer(f.admin_header);
    let expected = auth_token::TokenClaims { user_id: 1, scope: "admin", valid: true };
    t.assert_struct_eq(expected, claims, "admin token claims");
}

// @DisplayName("rejects missing or malformed Authorization header")
// @RepeatedTest(3)
fn test_malformed_header(t: Test&, f: Fixture&) {
    let claims = auth_token::parse_bearer("Basic abcdef");
    t.assert_false(claims.valid, "Basic auth should not parse as Bearer");
    t.assert_eq(0, claims.user_id, "invalid user_id must be 0");
}

// @Disabled("pending clock skew tolerance implementation in token verifier")
fn test_expired_token_clock_skew(t: Test&, f: Fixture&) {
    t.fail("not yet implemented");
}
