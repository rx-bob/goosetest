// Pinned import grammar and bytewise path ordering are checked independently.
namespace paths_test;

import goosetest.src.discovery.paths;

fn test_segments() {
    let valid: const u8[:][8] = ["_", "A", "a1", "snake_case", "inline", "from", "fields", "checkfree"];
    for name in valid {
        assert(discovery::import_segment(name));
    }
    let invalid: const u8[:][12] = [
        "", "1a", "bad-name", "a b", "a.b", "a/b", "a\\b", "é", "if", "i64", "self", "true",
    ];
    for name in invalid {
        assert( !discovery::import_segment(name));
    }
    for name in discovery::KEYWORDS {
        assert( !discovery::import_segment(name));
    }
    assert(discovery::goose_file("a.goose"));
    assert( !discovery::goose_file("a.goose.data"));
    assert( !discovery::goose_file("a.Goose"));
    assert(discovery::join_path("src/a", "b.goose") == "src/a/b.goose");
    assert(discovery::bytewise_less("src/A.goose", "src/a.goose"));
    assert(discovery::bytewise_less("src/a", "src/aa"));
    assert( !discovery::bytewise_less("same", "same"));
}
