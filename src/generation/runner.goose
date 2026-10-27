// Deterministic bounded fanout dispatch; each file imports every directly called module.
namespace generation;

import std;

import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.paths;
import src.generation.model;
import src.generation.suites;
import src.generation.validation;

fn generate(output: Output&, manifest: discovery::Manifest&, audit: discovery::MirrorAudit&) {
    assert( !output.complete && output.modules.len == 0);
    if discovery::manifest_status(manifest) != 0 || discovery::mirror_status(audit) != 0 || manifest.cases.len == 0 {
        fail(output, "", "generation requires a complete nonempty audited manifest");
        return;
    }
    validate(output, manifest);
    if output.error.len > 0 {
        return;
    }
    emit_cases(output, manifest);
    if output.error.len > 0 {
        return;
    }
    var count = manifest.cases.len;
    var level: i64 = 0;
    while count > 1 {
        let next = (count + 31) / 32;
        for group in 0..next {
            emit_dispatch(output, level, group, count);
        }
        if output.error.len > 0 {
            return;
        }
        count = next;
        level += 1;
    }
    emit_runner(output, manifest, level);
    add_module(output, "report.goose", embed_file("report.goose.data"));
    add_module(output, "completion.goose", embed_file("completion.goose.data"));
    output.complete = output.error.len == 0;
}

// Each suite range is scanned once for executability and once for emission.
fn emit_cases(output: Output&, manifest: discovery::Manifest&) {
    for suite in manifest.suites {
        var executable = false;
        let end = suite.first_case + suite.case_count;
        for index in suite.first_case..end {
            if !manifest.cases[index].disabled {
                executable = true;
            }
        }
        for index in suite.first_case..end {
            emit_case(output, manifest, index, executable);
            if output.error.len > 0 {
                return;
            }
        }
    }
}

fn child_module(level: i64, index: i64) -> u8[>..] {
    if level == 0 {
        return str("case_", index);
    }
    return str("dispatch_", level - 1, "_", index);
}

fn emit_dispatch(output: Output&, level: i64, group: i64, count: i64) {
    var out: u8[>..] = [];
    let name = str("dispatch_", level, "_", group);
    format(out, "// Generated bounded static dispatch.\nnamespace goosetest_generated_",
        name, ";\n\nimport goosetest;\n\n");
    let start = group * 32;
    let end = min(start + 32, count);
    var imports: i64[>..] = [];
    for index in start..end {
        imports.push(index);
    }
    sort(imports) {
        a,
        b => discovery::bytewise_less(child_module(level, a), child_module(level, b))
    };
    for index in imports {
        format(out, "import goosetest_generated.", child_module(level, index), ";\n");
    }
    out.append("\nfn run(t: goosetest::Test&) {\n");
    for index in start..end {
        format(out, "    goosetest_generated_", child_module(level, index), "::run(t);\n");
    }
    out.append("}\n");
    add_module(output, str(name, ".goose"), out);
}

fn emit_runner(output: Output&, manifest: discovery::Manifest&, level: i64) {
    var out: u8[>..] = [];
    let child = child_module(level, 0);
    out.append("// Generated entry behind the authored package root.\n");
    out.append("namespace goosetest_generated;\n\nimport goosetest;\n\n");
    if level > 0 {
        out.append("import goosetest_generated.completion;\n");
    }
    format(out, "import goosetest_generated.", child, ";\n");
    if level == 0 {
        out.append("import goosetest_generated.completion;\n");
    }
    out.append("import goosetest_generated.report;\n\n");
    out.append("fn run_all() -> i32 {\n    var cases: goosetest::CaseResult[>..] = [];\n");
    out.append("    var failures: goosetest::Failure[>..] = [];\n    var diagnostics: u8[>..] = [];\n");
    out.append("    var metadata: u8[>..] = [];\n    let limits = goosetest::Limits {\n");
    format(out, "        cases: ", manifest.cases.len, ",\n        metadata_bytes: ",
        metadata_size(manifest), ",\n        ..\n    };\n");
    out.append("    var results = goosetest::new_results(cases, failures, diagnostics, metadata, limits);\n");
    out.append("    var t = goosetest::Test {\n        results: results,\n        ..\n    };\n");
    format(out, "    goosetest_generated_", child, "::run(t);\n");
    format(out, "    goosetest_generated_report::report(results, ", manifest.cases.len, ");\n");
    out.append("    return goosetest_generated_completion::finish(goosetest::run_status(results));\n}\n");
    add_module(output, "runner.goose", out);
}

fn metadata_size(manifest: discovery::Manifest&) -> i64 {
    var total: i64 = 0;
    for entry in manifest.cases {
        let suite = manifest.suites[entry.suite_index];
        total += suite.path.length + suite.namespace_name.length + entry.name.length + entry.display_name.length;
        if entry.disabled {
            total += entry.disabled_reason.length;
        } else if suite.before_all.present {
            total += "suite setup failed".len;
        }
    }
    for suite in manifest.suites {
        if suite.before_all.present {
            total += suite.path.length + suite.namespace_name.length + "before_all".len;
        }
        if suite.after_all.present {
            total += suite.path.length + suite.namespace_name.length + "after_all".len;
        }
    }
    return total;
}
