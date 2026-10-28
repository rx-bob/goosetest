// Compiler argv is built as literal arguments and never interpreted by a shell.
namespace build;

import src.arguments;

fn append_arguments(argv: const u8[:][>..]&, compiler: u8[:], entry: u8[:], destination: u8[:],
    profile: arguments::Profile, offline: bool) {
    assert(argv.len == 0);
    argv.push(compiler);
    argv.push("build");
    argv.push(entry);
    if profile == arguments::Profile.Debug {
        argv.push("-O0");
        argv.push("--debug");
    } else {
        argv.push("-O2");
    }
    if offline {
        argv.push("--offline");
    }
    argv.push("-o");
    argv.push(destination);
}
