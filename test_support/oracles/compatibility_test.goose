// Standalone bootstrap oracle, independent of the future goosetest runtime.
import goosetest from "../compatibility/contract";

import probes from "../compatibility";
import probes.scenarios;

fn main() {
    compatibility_test::test_bridge_recovery();
    compatibility_test::test_nested_boundary();
    compatibility_test::test_storage();
}
