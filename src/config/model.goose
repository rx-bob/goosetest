// Bounded project configuration owns decoded strings and normalized target records.
namespace config;

let MAX_TARGETS = 64;
let MAX_ROOTS = 64;
let MAX_PAIRS = 64;
let MAX_EXCLUSIONS = 256;

enum JsonKind {
    Object,
    Array,
    String,
    Number,
    True,
    False,
    Null
}

struct JsonToken {
    kind: JsonKind,
    text: Span,
    end: i64,
}

struct Reader {
    source: const u8[:],
    index: i64 = 0,
    text: u8[>..]&,
    tokens: JsonToken[>..]&,
    error: const u8[:] = "",
}

struct Span {
    offset: i64,
    length: i64
}

enum TestKind {
    Unit,
    Integration
}

enum MirrorPolicy {
    Off,
    Strict
}

struct TestRoot {
    path: Span,
    kind: TestKind,
    target: i64
}

struct Exclusion {
    path: Span,
    directory: bool,
    target: i64
}

struct MirrorPair {
    source: Span,
    tests: Span,
    target: i64
}

struct Target {
    name: Span,
    entry: Span,
    root_start: i64,
    root_count: i64,
    exclusion_start: i64,
    exclusion_count: i64,
    pair_start: i64,
    pair_count: i64,
    policy: MirrorPolicy,
}

struct Configuration {
    text: u8[>..]&,
    targets: Target[>..]&,
    roots: TestRoot[>..]&,
    exclusions: Exclusion[>..]&,
    pairs: MirrorPair[>..]&,
    configured: bool = false,
    error: const u8[:] = "",
    field: const u8[:] = "",
}

struct MirrorRange {
    start: i64,
    policy: MirrorPolicy,
    error: bool,
}

fn new_configuration(
    text: u8[>..]&, targets: Target[>..]&, roots: TestRoot[>..]&, exclusions: Exclusion[>..]&, pairs: MirrorPair[>..]&
) -> Configuration {
    assert(text.len == 0);
    assert(targets.len == 0);
    assert(roots.len == 0);
    assert(exclusions.len == 0);
    assert(pairs.len == 0);
    return Configuration {
        text: text,
        targets: targets,
        roots: roots,
        exclusions: exclusions,
        pairs: pairs,
    };
}

fn text_value(configuration: Configuration&, value: Span) -> const u8[:] {
    return configuration.text[value.offset..value.offset + value.length];
}
