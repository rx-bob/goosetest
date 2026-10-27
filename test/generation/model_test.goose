// Generation errors retain their first cause and never report partial modules as complete.
namespace generation_model_test;

import goosetest.src.generation.model;
import goosetest.test_support.generation;

fn test_invalid_limits() {
    for index in 0..3 {
        var limits = generation::Limits {
        };
        if index == 0 {
            limits.max_files = - 1;
        }
        if index == 1 {
            limits.max_source_bytes = - 1;
        }
        if index == 2 {
            limits.max_path_bytes = - 1;
        }
        generation_support::with_output(limits) {
            output =>
            assert(generation::status(output) == 2 && output.error.len > 0);
            generation::fail(output, "later", "must not replace the first error");
            assert(output.error == ": generation limits must be nonnegative");
        }
    }
}
