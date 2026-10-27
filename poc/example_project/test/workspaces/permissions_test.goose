import std;
import goosetest;
import src.workspaces.permissions;

// ============================================================================
// Mirrored Test: test/workspaces/permissions_test.goose <-> src/workspaces/permissions.goose
// ============================================================================
namespace workspaces_permissions_test;

struct Fixture {
    viewer_header: const u8[:] = "",
}

fn before_each(f: Fixture&) {
    f.viewer_header = "Bearer tok_viewer";
}

fn after_each(f: Fixture&) {
    f.viewer_header = "";
}

// @DisplayName("grants write access to admin token")
fn test_admin_can_write(t: Test&, f: Fixture&) {
    let decision = workspaces_permissions::check_write_access("Bearer tok_admin");
    t.assert_true(decision.allowed, "admin must be allowed");
    t.assert_eq("admin", decision.effective_role);
}

// @DisplayName("denies write access to viewer role (intentional failure demo)")
fn test_viewer_write_denied_demo_diff(t: Test&, f: Fixture&) {
    let actual = workspaces_permissions::check_write_access(f.viewer_header);
    // Intentionally expect `allowed: true` to showcase JUnit struct field diffing:
    let expected = workspaces_permissions::AccessDecision {
        allowed: true,
        effective_role: "viewer",
        reason: "ok",
    };
    t.assert_struct_eq(expected, actual, "viewer write check");
}
