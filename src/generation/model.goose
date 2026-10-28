// Owned generated modules are staged in bounded arenas before any filesystem writes.
namespace generation;

import std;

import src.discovery.manifest;

struct Span {
    offset: i64 = 0,
    length: i64 = 0
}
struct Module {
    path: Span,
    source: Span
}
struct Limits {
    max_files: i64 = 70000,
    max_source_bytes: i64 = 67108864,
    max_path_bytes: i64 = 4194304,
}
struct Output {
    modules: Module[>..]&,
    paths: u8[>..]&,
    sources: u8[>..]&,
    error: u8[>..]&,
    limits: Limits,
    complete: bool = false,
}

fn new_output(modules: Module[>..]&, paths: u8[>..]&, sources: u8[>..]&, error: u8[>..]&,
    limits: Limits = Limits {
    }) -> Output {
    assert(modules.len == 0);
    assert(paths.len == 0);
    assert(sources.len == 0);
    assert(error.len == 0);
    var output = Output {
        modules: modules,
        paths: paths,
        sources: sources,
        error: error,
        limits: limits,
        ..
    };
    if limits.max_files < 0 || limits.max_source_bytes < 0 || limits.max_path_bytes < 0 {
        fail(output, "", "generation limits must be nonnegative");
    }
    return output;
}

fn fail(output: Output&, path: u8[:], message: u8[:]) {
    if output.error.len == 0 {
        format(output.error, path, ": ", message);
    }
}

fn add_module(output: Output&, path: u8[:], source: u8[:]) {
    var end = source.len;
    while end > 1 && source[end - 1] == '\n' && source[end - 2] == '\n' {
        end -= 1;
    }
    let content = source[..end];
    if output.error.len > 0 {
        return;
    }
    if output.modules.len >= output.limits.max_files {
        fail(output, path, "max_files exceeded");
        return;
    }
    if content.len > output.limits.max_source_bytes - output.sources.len {
        fail(output, path, "max_source_bytes exceeded");
        return;
    }
    if path.len > output.limits.max_path_bytes - output.paths.len {
        fail(output, path, "max_path_bytes exceeded");
        return;
    }
    assert(content.len <= 65536);
    let module = Module {
        path: Span {
            offset: output.paths.len,
            length: path.len
        },
        source: Span {
            offset: output.sources.len,
            length: content.len
        }
    };
    output.paths.append(path);
    output.sources.append(content);
    output.modules.push(module);
}

fn module_path(output: Output&, module: Module) -> const u8[:] {
    return output.paths[module.path.offset..module.path.offset + module.path.length];
}

fn module_source(output: Output&, module: Module) -> const u8[:] {
    return output.sources[module.source.offset..module.source.offset + module.source.length];
}

fn generated_module_path(manifest: discovery::Manifest&, name: u8[:]) -> u8[>..] {
    let target = discovery::manifest_text(manifest, manifest.target_name);
    if target.len == 0 {
        return str(name);
    }
    return str(target, "/", name);
}

fn generated_import_path(manifest: discovery::Manifest&, name: u8[:]) -> u8[>..] {
    let target = discovery::manifest_text(manifest, manifest.target_name);
    if target.len == 0 {
        return str("goosetest_generated.", name);
    }
    return str("goosetest_generated.", target, ".", name);
}

fn source_identity_path(manifest: discovery::Manifest&, path: u8[:]) -> u8[>..] {
    let target = discovery::manifest_text(manifest, manifest.target_name);
    if target.len == 0 {
        return str(path);
    }
    return str(target, "::", path);
}

fn completion_path(manifest: discovery::Manifest&) -> u8[>..] {
    let target = discovery::manifest_text(manifest, manifest.target_name);
    if target.len == 0 {
        return "goosetest_generated/completion";
    }
    return str("goosetest_generated/", target, "/completion");
}

fn status(output: Output&) -> i32 {
    if output.complete && output.error.len == 0 {
        return 0;
    }
    return 2;
}
