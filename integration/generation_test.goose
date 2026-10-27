// Transitional generation driver: parent owns a fresh destination and all cleanup.
import goosetest from "..";
import goosetest.src.discovery.files;
import goosetest.src.discovery.manifest;
import goosetest.src.discovery.mirror;
import goosetest.src.discovery.model;
import goosetest.src.generation.model;
import goosetest.src.generation.runner;

import os;
import std;

fn main() {
    assert(arg_count() == 3);
    var project: u8[>..] = [];
    var destination: u8[>..] = [];
    arg(1, project);
    arg(2, destination);
    var files: discovery::SourceFile[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var scan_error: u8[>..] = [];
    var inventory = discovery::new_inventory(files, paths, sources, scan_error);
    discovery::scan(inventory, project);
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var syntax_error: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, syntax_error);
    discovery::inspect_project(audit, manifest, inventory);
    if discovery::project_status(audit, manifest) != 0 {
        print("invalid project for generation");
        exit(2);
    }
    exit(emit(manifest, audit, destination));
}

fn emit(manifest: discovery::Manifest&, audit: discovery::MirrorAudit&, destination: u8[:]) -> i32 {
    var modules: generation::Module[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var errors: u8[>..] = [];
    var output = generation::new_output(modules, paths, sources, errors);
    generation::generate(output, manifest, audit);
    if generation::status(output) != 0 {
        print(output.error);
        return 2;
    }
    assert( !is_dir(destination) && !file_exists(destination));
    assert(make_dir(destination));
    for module in output.modules {
        assert(write_file(str(destination, "/", generation::module_path(output, module)),
            generation::module_source(output, module)));
    }
    print("generated ", output.modules.len, " modules for ", manifest.cases.len, " cases");
    return 0;
}
