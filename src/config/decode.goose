// Schema decoding validates fields, limits and lexical project-relative paths.
namespace config;

import src.config.decode_fields;
import src.config.json;
import src.config.model;
import src.config.validation;
import src.discovery.paths;

fn decode_configuration(configuration: Configuration&, tokens: JsonToken[>..]&) -> bool {
    let version = member(tokens, configuration.text, 0, "version");
    let targets = member(tokens, configuration.text, 0, "targets");
    if has_unknown(configuration, tokens, 0, AllowedFields {
            a: "version", b: "targets", c: "", d: "", e: ""
        }) {
        configuration.error = "unknown top-level field";
        configuration.field = "goosetest.json";
        return false;
    }
    if version < 0 || targets < 0 {
        configuration.error = "required field is missing";
        configuration.field = "version or targets";
        return false;
    }
    let version_text = token_text(configuration, tokens[version]);
    if tokens[version].kind != JsonKind.Number || version_text != "1" {
        configuration.error = "unsupported configuration version";
        configuration.field = "version";
        return false;
    }
    if tokens[targets].kind != JsonKind.Array {
        configuration.error = "expected array";
        configuration.field = "targets";
        return false;
    }
    let end = tokens[targets].end;
    var index = targets + 1;
    while index < end {
        if configuration.targets.len >= MAX_TARGETS {
            configuration.error = "target count exceeds 64";
            configuration.field = "targets";
            return false;
        }
        if !decode_target(configuration, tokens, index) {
            return false;
        }
        index = tokens[index].end;
    }
    if configuration.targets.len == 0 {
        configuration.error = "targets must not be empty";
        configuration.field = "targets";
        return false;
    }
    return validate_overlaps(configuration);
}

fn decode_target(configuration: Configuration&, tokens: JsonToken[>..]&, object: i64) -> bool {
    let fields = target_fields(configuration, tokens, object);
    if fields.name < 0 {
        return false;
    }
    let target_index = configuration.targets.len;
    if !validate_target_identity(configuration, tokens, fields) {
        return false;
    }
    let root_start = configuration.roots.len;
    if !decode_roots(configuration, tokens, fields.tests, target_index) {
        return false;
    }
    let exclusion_start = configuration.exclusions.len;
    if !decode_exclusions(configuration, tokens, fields.exclude, target_index) {
        return false;
    }
    let mirror = decode_mirror(configuration, tokens, fields.mirror, target_index, root_start);
    if mirror.error {
        return false;
    }
    configuration.targets.push(Target {
            name: tokens[fields.name].text,
            entry: tokens[fields.entry].text,
            root_start: root_start,
            root_count: configuration.roots.len - root_start,
            exclusion_start: exclusion_start,
            exclusion_count: configuration.exclusions.len - exclusion_start,
            pair_start: mirror.start,
            pair_count: configuration.pairs.len - mirror.start,
            policy: mirror.policy,
        });
    return true;
}

struct TargetFields {
    name: i64,
    entry: i64,
    tests: i64,
    exclude: i64,
    mirror: i64,
}

fn target_fields(configuration: Configuration&, tokens: JsonToken[>..]&, object: i64) -> TargetFields {
    if tokens[object].kind != JsonKind.Object || has_unknown(configuration, tokens, object, AllowedFields {
            a: "name", b: "entry", c: "tests", d: "exclude", e: "mirror"
        }) {
        configuration.error = "invalid or unknown target field";
        configuration.field = "targets";
        return TargetFields {
            name: -1,
            entry: -1,
            tests: -1,
            exclude: -1,
            mirror: -1
        };
    }
    let name = member(tokens, configuration.text, object, "name");
    let entry = member(tokens, configuration.text, object, "entry");
    let tests = member(tokens, configuration.text, object, "tests");
    if name < 0 || entry < 0 || tests < 0 {
        configuration.error = "required field is missing";
        configuration.field = "targets.name, targets.entry, or targets.tests";
        return TargetFields {
            name: -1,
            entry: entry,
            tests: tests,
            exclude: -1,
            mirror: -1
        };
    }
    return TargetFields {
        name: name,
        entry: entry,
        tests: tests,
        exclude: member(tokens, configuration.text, object, "exclude"),
        mirror: member(tokens, configuration.text, object, "mirror"),
    };
}

fn validate_target_identity(configuration: Configuration&, tokens: JsonToken[>..]&, fields: TargetFields) -> bool {
    if tokens[fields.name].kind != JsonKind.String
        || tokens[fields.entry].kind != JsonKind.String
        || tokens[fields.tests].kind != JsonKind.Array {
        configuration.error = "wrong field type";
        configuration.field = "targets.name, targets.entry, or targets.tests";
        return false;
    }
    let name = token_text(configuration, tokens[fields.name]);
    if !valid_target_name(name) {
        configuration.error = "invalid target name";
        configuration.field = "targets.name";
        return false;
    }
    if !valid_path(token_text(configuration, tokens[fields.entry]), true, false) {
        configuration.error = "invalid project-relative Goose entry path";
        configuration.field = "targets.entry";
        return false;
    }
    for prior in configuration.targets {
        if equal(text_value(configuration, prior.name), name) {
            configuration.error = "duplicate target name";
            configuration.field = "targets.name";
            return false;
        }
    }
    return true;
}
