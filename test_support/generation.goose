// Bounded output owners and a minimal audited syntax input for generator unit checks.
namespace generation_support;

import src.discovery.mirror;
import src.generation.model;

fn with_output<F>(limits: generation::Limits = generation::Limits {
    }) {
    var modules: generation::Module[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var errors: u8[>..] = [];
    var output = generation::new_output(modules, paths, sources, errors, limits);
    F(output);
}

fn with_audit<F>() {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    audit.complete = true;
    F(audit);
}
