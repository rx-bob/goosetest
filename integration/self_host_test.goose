// Generated wrappers carry source identity into the real executing runtime context.
namespace self_host_integration_test;

import goosetest;

fn test_generated_identity(outer: goosetest::Test&) {
    outer.assert_true(outer.active);
    outer.assert_true(outer.results.active);
    outer.assert_true(outer.current_case >= 0);
    let identity = outer.results.cases[outer.current_case].identity;
    outer.assert_eq("integration/self_host_test.goose", goosetest::metadata_text(outer.results, identity.test_path));
    outer.assert_eq("self_host_integration_test", goosetest::metadata_text(outer.results, identity.namespace_name));
    outer.assert_eq("test_generated_identity", goosetest::metadata_text(outer.results, identity.function_name));
    outer.assert_true(identity.declaration_line > 0);
}
