// Path and identifier channels cannot carry literals or bypass generated style bounds.
namespace validation_test;

import std;

import goosetest.src.discovery.model;
import goosetest.src.generation.validation;

fn test_paths() {
    assert(generation::valid_path("test/nested/name_test.goose", discovery::RootKind.Unit));
    assert(generation::valid_path("integration/flow_test.goose", discovery::RootKind.Integration));
    assert( !generation::valid_path("test/../name_test.goose", discovery::RootKind.Unit));
    assert( !generation::valid_path("test/name_test.goose", discovery::RootKind.Integration));
    assert( !generation::valid_path("test/evil;name_test.goose", discovery::RootKind.Unit));
    var name: u8[>..] = [];
    for index in 0..48 {
        name.push('a');
    }
    assert(generation::identifier(name));
    name.push('a');
    assert( !generation::identifier(name));
}

fn test_path_bounds() {
    var directory: u8[>..] = [];
    var base: u8[>..] = [];
    for index in 0..40 {
        directory.push('a');
    }
    for index in 0..43 {
        base.push('b');
    }
    let exact = str("test/", directory, "/", base, "_test.goose");
    assert(exact.len == 100 && generation::valid_path(exact, discovery::RootKind.Unit));
    directory.push('a');
    let over = str("test/", directory, "/", base, "_test.goose");
    assert(over.len == 101 && !generation::valid_path(over, discovery::RootKind.Unit));
}
