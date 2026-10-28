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

fn cache_home(path: u8[>..]&, root: u8[:], target: u8[:], profile: arguments::Profile) -> bool {
    assert(path.len == 0);
    let mode: const u8[:] = if profile == arguments::Profile.Debug {
        "debug"
    } else {
        "optimized"
    };
    let default_base: const u8[:] = "./goosetest_generated/cache";
    let prefix = if root.len == 0 {
        default_base.len
    } else if root[0] == '/' {
        root.len
    } else {
        root.len + 2
    };
    let suffix = target.len + mode.len + 2;
    if prefix > 4095 - suffix {
        return false;
    }
    if root.len == 0 {
        path.append(default_base);
    } else if root[0] == '/' {
        path.append(root);
    } else {
        path.append("./");
        path.append(root);
    }
    path.push('/');
    path.append(target);
    path.push('/');
    path.append(mode);
    return true;
}
