import std;
import src.auth.token;

namespace workspaces_permissions;

struct AccessDecision {
    allowed: bool,
    effective_role: const u8[:],
    reason: const u8[:],
}

fn check_write_access(auth_header: const u8[:]) -> AccessDecision {
    let claims = auth_token::parse_bearer(auth_header);
    if !claims.valid {
        return AccessDecision { allowed: false, effective_role: "none", reason: "unauthorized" };
    }
    if claims.scope == "admin" {
        return AccessDecision { allowed: true, effective_role: "admin", reason: "ok" };
    }
    return AccessDecision { allowed: false, effective_role: claims.scope, reason: "insufficient_role" };
}
