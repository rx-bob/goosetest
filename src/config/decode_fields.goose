// Schema field lookup and leaf record decoding.
namespace config;

import src.config.json;
import src.config.model;
import src.config.validation;

struct AllowedFields {
    a: const u8[:],
    b: const u8[:],
    c: const u8[:],
    d: const u8[:],
    e: const u8[:],
}

struct MirrorHeader {
    pair_token: i64,
    policy: MirrorPolicy,
    error: bool,
}

fn decode_roots(configuration: Configuration&, tokens: JsonToken[>..]&, tests: i64, target: i64) -> bool {
    let start = configuration.roots.len;
    var item = tests + 1;
    while item < tokens[tests].end {
        if configuration.roots.len - start >= MAX_ROOTS {
            configuration.error = "test root count exceeds 64";
            configuration.field = "targets.tests";
            return false;
        }
        if !decode_root(configuration, tokens, item, target) {
            return false;
        }
        item = tokens[item].end;
    }
    if configuration.roots.len == start {
        configuration.error = "tests must not be empty";
        configuration.field = "targets.tests";
        return false;
    }
    return true;
}

fn decode_exclusions(configuration: Configuration&, tokens: JsonToken[>..]&, exclude: i64, target: i64) -> bool {
    if exclude < 0 {
        return true;
    }
    if tokens[exclude].kind != JsonKind.Array {
        configuration.error = "expected array";
        configuration.field = "targets.exclude";
        return false;
    }
    let start = configuration.exclusions.len;
    var item = exclude + 1;
    while item < tokens[exclude].end {
        if configuration.exclusions.len - start >= MAX_EXCLUSIONS {
            configuration.error = "exclusion count exceeds 256";
            configuration.field = "targets.exclude";
            return false;
        }
        if tokens[item].kind != JsonKind.String {
            configuration.error = "expected path string";
            configuration.field = "targets.exclude";
            return false;
        }
        let path = token_text(configuration, tokens[item]);
        let directory = path.len > 0 && path[path.len - 1] == '/';
        let clean = if directory {
            path[..path.len - 1]
        } else {
            path
        };
        if !valid_path(clean, false, true) {
            configuration.error = "invalid exclusion path";
            configuration.field = "targets.exclude";
            return false;
        }
        configuration.exclusions.push(Exclusion {
                path: tokens[item].text,
                directory: directory,
                target: target
            });
        item = tokens[item].end;
    }
    return true;
}

fn decode_mirror(
    configuration: Configuration&, tokens: JsonToken[>..]&, mirror: i64, target: i64, root_start: i64
) -> MirrorRange {
    let start = configuration.pairs.len;
    if mirror < 0 {
        return mirror_result(start, MirrorPolicy.Off, false);
    }
    let header = parse_mirror_header(configuration, tokens, mirror);
    if header.error {
        return mirror_result(start, MirrorPolicy.Off, true);
    }
    if !decode_pairs(configuration, tokens, header.pair_token, target, start) {
        return mirror_result(start, header.policy, true);
    }
    if !validate_mirror_pairs(configuration, header.policy, start, root_start) {
        return mirror_result(start, header.policy, true);
    }
    return mirror_result(start, header.policy, false);
}

fn parse_mirror_header(configuration: Configuration&, tokens: JsonToken[>..]&, mirror: i64) -> MirrorHeader {
    let fields = AllowedFields {
        a: "policy",
        b: "pairs",
        c: "",
        d: "",
        e: ""
    };
    if tokens[mirror].kind != JsonKind.Object || has_unknown(configuration, tokens, mirror, fields) {
        configuration.error = "malformed mirror object";
        configuration.field = "targets.mirror";
        return MirrorHeader {
            pair_token: -1,
            policy: MirrorPolicy.Off,
            error: true
        };
    }
    let policy_token = member(tokens, configuration.text, mirror, "policy");
    let pair_token = member(tokens, configuration.text, mirror, "pairs");
    if policy_token < 0 || pair_token < 0
        || tokens[policy_token].kind != JsonKind.String
        || tokens[pair_token].kind != JsonKind.Array {
        configuration.error = "mirror requires policy and pairs";
        configuration.field = "targets.mirror";
        return MirrorHeader {
            pair_token: -1,
            policy: MirrorPolicy.Off,
            error: true
        };
    }
    let value = token_text(configuration, tokens[policy_token]);
    if value == "off" {
        return MirrorHeader {
            pair_token: pair_token,
            policy: MirrorPolicy.Off,
            error: false
        };
    }
    if value == "strict" {
        return MirrorHeader {
            pair_token: pair_token,
            policy: MirrorPolicy.Strict,
            error: false
        };
    }
    configuration.error = "mirror policy must be off or strict";
    configuration.field = "targets.mirror.policy";
    return MirrorHeader {
        pair_token: -1,
        policy: MirrorPolicy.Off,
        error: true
    };
}

fn validate_mirror_pairs(configuration: Configuration&, policy: MirrorPolicy, start: i64, root_start: i64) -> bool {
    if policy == MirrorPolicy.Off && configuration.pairs.len != start {
        configuration.error = "mirror off requires empty pairs";
        configuration.field = "targets.mirror.pairs";
        return false;
    }
    if policy == MirrorPolicy.Strict && configuration.pairs.len == start {
        configuration.error = "strict mirror requires pairs";
        configuration.field = "targets.mirror.pairs";
        return false;
    }
    return policy != MirrorPolicy.Strict || validate_strict_mirror(configuration, start, root_start);
}

fn mirror_result(start: i64, policy: MirrorPolicy, error: bool) -> MirrorRange {
    return MirrorRange {
        start: start,
        policy: policy,
        error: error
    };
}

fn decode_pairs(configuration: Configuration&, tokens: JsonToken[>..]&, array: i64, target: i64, start: i64) -> bool {
    var item = array + 1;
    while item < tokens[array].end {
        if configuration.pairs.len - start >= MAX_PAIRS {
            configuration.error = "mirror pair count exceeds 64";
            configuration.field = "targets.mirror.pairs";
            return false;
        }
        if !decode_pair(configuration, tokens, item, target) {
            return false;
        }
        item = tokens[item].end;
    }
    return true;
}

fn validate_strict_mirror(configuration: Configuration&, pair_start: i64, root_start: i64) -> bool {
    for root in configuration.roots[root_start..] {
        if root.kind == TestKind.Unit && !has_pair_for_root(configuration, root, pair_start) {
            configuration.error = "strict mirror needs a pair for each unit root";
            configuration.field = "targets.mirror.pairs";
            return false;
        }
    }
    for i in pair_start..configuration.pairs.len {
        for j in pair_start..i {
            let tests_i = configuration.pairs[i].tests;
            let tests_j = configuration.pairs[j].tests;
            if equal(text_value(configuration, tests_i), text_value(configuration, tests_j)) {
                configuration.error = "duplicate mirror tests path";
                configuration.field = "targets.mirror.pairs.tests";
                return false;
            }
            let source_i = configuration.pairs[i].source;
            let source_j = configuration.pairs[j].source;
            if overlaps(text_value(configuration, source_i), text_value(configuration, source_j)) {
                configuration.error = "strict source roots overlap";
                configuration.field = "targets.mirror.pairs";
                return false;
            }
        }
    }
    return true;
}

fn has_pair_for_root(configuration: Configuration&, root: TestRoot, pair_start: i64) -> bool {
    for pair in configuration.pairs[pair_start..] {
        if equal(text_value(configuration, pair.tests), text_value(configuration, root.path)) {
            return true;
        }
    }
    return false;
}

fn decode_root(configuration: Configuration&, tokens: JsonToken[>..]&, object: i64, target: i64) -> bool {
    if tokens[object].kind != JsonKind.Object || has_unknown(configuration, tokens, object, AllowedFields {
            a: "path", b: "kind", c: "", d: "", e: ""
        }) {
        configuration.error = "invalid test root object";
        configuration.field = "targets.tests";
        return false;
    }
    let path = member(tokens, configuration.text, object, "path");
    let kind = member(tokens, configuration.text, object, "kind");
    if path < 0 || kind < 0 || tokens[path].kind != JsonKind.String || tokens[kind].kind != JsonKind.String {
        configuration.error = "test root requires path and kind strings";
        configuration.field = "targets.tests";
        return false;
    }
    let path_text = token_text(configuration, tokens[path]);
    let kind_text = token_text(configuration, tokens[kind]);
    if !valid_path(path_text, false, false) {
        configuration.error = "invalid test root path";
        configuration.field = "targets.tests.path";
        return false;
    }
    var root_kind = TestKind.Unit;
    if kind_text == "unit" {
        root_kind = TestKind.Unit;
    } else if kind_text == "integration" {
        root_kind = TestKind.Integration;
    } else {
        configuration.error = "test kind must be unit or integration";
        configuration.field = "targets.tests.kind";
        return false;
    }
    configuration.roots.push(TestRoot {
            path: tokens[path].text,
            kind: root_kind,
            target: target
        });
    return true;
}

fn decode_pair(configuration: Configuration&, tokens: JsonToken[>..]&, object: i64, target: i64) -> bool {
    if tokens[object].kind != JsonKind.Object || has_unknown(configuration, tokens, object, AllowedFields {
            a: "source", b: "tests", c: "", d: "", e: ""
        }) {
        configuration.error = "invalid mirror pair object";
        configuration.field = "targets.mirror.pairs";
        return false;
    }
    let source = member(tokens, configuration.text, object, "source");
    let tests = member(tokens, configuration.text, object, "tests");
    if source < 0 || tests < 0 || tokens[source].kind != JsonKind.String || tokens[tests].kind != JsonKind.String {
        configuration.error = "mirror pair requires source and tests strings";
        configuration.field = "targets.mirror.pairs";
        return false;
    }
    let source_path = token_text(configuration, tokens[source]);
    let test_path = token_text(configuration, tokens[tests]);
    if !valid_path(source_path, false, false) || !valid_path(test_path, false, false) {
        configuration.error = "invalid mirror pair path";
        configuration.field = "targets.mirror.pairs";
        return false;
    }
    var unit_root = false;
    for root in configuration.roots {
        if root.target == target && root.kind == TestKind.Unit && equal(token_text(configuration, JsonToken {
                kind: JsonKind.String, text: root.path, end: 0
            }), token_text(configuration, tokens[tests])) {
            unit_root = true;
        }
    }
    if !unit_root {
        configuration.error = "mirror tests path must name a unit root";
        configuration.field = "targets.mirror.pairs.tests";
        return false;
    }
    configuration.pairs.push(MirrorPair {
            source: tokens[source].text,
            tests: tokens[tests].text,
            target: target
        });
    return true;
}

fn member(tokens: JsonToken[>..]&, text: u8[>..]&, object: i64, name: u8[:]) -> i64 {
    var index = object + 1;
    let end = tokens[object].end;
    while index < end {
        let key = tokens[index];
        let value = index + 1;
        if key.kind == JsonKind.String && equal(text[key.text.offset..key.text.offset + key.text.length], name) {
            return value;
        }
        index = tokens[value].end;
    }
    return -1;
}

fn has_unknown(configuration: Configuration&, tokens: JsonToken[>..]&, object: i64, allowed: AllowedFields) -> bool {
    if tokens[object].kind != JsonKind.Object {
        return false;
    }
    var index = object + 1;
    let end = tokens[object].end;
    while index < end {
        let key = tokens[index];
        var known = false;
        let value = token_text(configuration, key);
        if equal(value, allowed.a) || equal(value, allowed.b)
            || (allowed.c.len > 0 && equal(value, allowed.c))
            || (allowed.d.len > 0 && equal(value, allowed.d))
            || (allowed.e.len > 0 && equal(value, allowed.e)) {
            known = true;
        }
        if !known {
            return true;
        }
        index = tokens[index + 1].end;
    }
    return false;
}

fn token_text(configuration: Configuration&, token: JsonToken) -> const u8[:] {
    return configuration.text[token.text.offset..token.text.offset + token.text.length];
}
