import std;

namespace auth_token;

struct TokenClaims {
    user_id: i64,
    scope: const u8[:],
    valid: bool,
}

fn parse_bearer(header: const u8[:]) -> TokenClaims {
    if !starts_with(header, "Bearer ") || header.len <= 7 {
        return TokenClaims { user_id: 0, scope: "", valid: false };
    }
    let raw = trim(header[7..]);
    if raw == "tok_admin" {
        return TokenClaims { user_id: 1, scope: "admin", valid: true };
    }
    if raw == "tok_viewer" {
        return TokenClaims { user_id: 2, scope: "viewer", valid: true };
    }
    return TokenClaims { user_id: 0, scope: "", valid: false };
}
