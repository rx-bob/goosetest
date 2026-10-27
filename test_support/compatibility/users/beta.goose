// Exercises the same bridge from another namespace with const-generic messages.
namespace beta_test;

import goosetest;

fn test_pass(t: goosetest::Test&) {
    var message: u8[>..] = [];
    message.append("mutable message");
    t.assert_eq(3, 3, message);
    t.assert_eq("literal", "literal", "literal message");
    t.reached = true;
}
