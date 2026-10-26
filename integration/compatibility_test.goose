// Standalone bootstrap oracle, independent of the future goosetest runtime.
import goosetest from "./fixtures/compatibility/contract";

import fixtures.compatibility.scenarios;

fn main() {
    compatibility_test::test_bridge_recovery();
    compatibility_test::test_nested_boundary();
    compatibility_test::test_storage();
}
