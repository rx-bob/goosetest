// Completion evidence is written only after generated execution and reporting return.
namespace goosetest_generated_completion;

import os;
import std;

fn finish(status: i32) -> i32 {
    if arg_count() == 2 {
        var flag: u8[>..] = [];
        arg(1, flag);
        if flag == "--goosetest-completion" {
            if !write_file("goosetest_generated/completion", str(status, "\n")) {
                write_stderr("ERROR: cannot write completion record; run incomplete.\n");
                return 2;
            }
        }
    }
    return status;
}
