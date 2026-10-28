// Deterministic bounded fanout dispatch; each file imports every directly called module.
namespace generation;

import std;

import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.paths;
import src.discovery.selection;
import src.generation.model;
import src.generation.suites;
import src.generation.validation;

fn generate(output: Output&, manifest: discovery::Manifest&, audit: discovery::MirrorAudit&,
    options: selection::Options = selection::Options {
    }, fail_fast: bool = false) {
    assert(!output.complete);
    assert(output.modules.len == 0);
    if discovery::manifest_status(manifest) != 0 || !discovery::mirror_valid(audit) || manifest.cases.len == 0 {
        fail(output, "", "generation requires a complete nonempty audited manifest");
        return;
    }
    validate(output, manifest);
    if output.error.len > 0 {
        return;
    }
    let selected = selection::count(manifest, options);
    if selected == 0 {
        fail(output, "", "selection matched no cases");
        return;
    }
    emit_cases(output, manifest, options);
    if output.error.len > 0 {
        return;
    }
    var count = manifest.cases.len;
    var level: i64 = 0;
    while count > 1 {
        let next = (count + 31) / 32;
        for group in 0..next {
            emit_dispatch(output, manifest, level, group, count);
        }
        if output.error.len > 0 {
            return;
        }
        count = next;
        level += 1;
    }
    emit_runner(output, manifest, level, selected, fail_fast);
    add_module(output, generated_module_path(manifest, "report.goose"), embed_file("report.goose.data"));
    add_module(output, generated_module_path(manifest, "completion.goose"), embed_file("completion.goose.data"));
    output.complete = output.error.len == 0;
}

// Each suite range is scanned once for executability and once for emission.
fn emit_cases(output: Output&, manifest: discovery::Manifest&, options: selection::Options) {
    for suite in manifest.suites {
        var executable = false;
        let end = suite.first_case + suite.case_count;
        for index in suite.first_case..end {
            if !manifest.cases[index].disabled && selection::matches(manifest, manifest.cases[index], options) {
                executable = true;
            }
        }
        for index in suite.first_case..end {
            let selected = selection::matches(manifest, manifest.cases[index], options);
            emit_case(output, manifest, index, executable, selected);
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

fn emit_dispatch(output: Output&, manifest: discovery::Manifest&, level: i64, group: i64, count: i64) {
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
        format(out, "import ", generated_import_path(manifest, child_module(level, index)), ";\n");
    }
    out.append("\nfn run(t: goosetest::Test&) {\n");
    for index in start..end {
        format(out, "    goosetest_generated_", child_module(level, index), "::run(t);\n");
    }
    out.append("}\n");
    add_module(output, generated_module_path(manifest, str(name, ".goose")), out);
}

fn emit_runner(output: Output&, manifest: discovery::Manifest&, level: i64, selected: i64, fail_fast: bool) {
    var out: u8[>..] = [];
    let child = child_module(level, 0);
    out.append("// Generated entry behind the authored package root.\n");
    out.append("namespace goosetest_generated;\n\nimport goosetest;\n\n");
    if level > 0 {
        format(out, "import ", generated_import_path(manifest, "completion"), ";\n");
    }
    format(out, "import ", generated_import_path(manifest, child), ";\n");
    if level == 0 {
        format(out, "import ", generated_import_path(manifest, "completion"), ";\n");
    }
    format(out, "import ", generated_import_path(manifest, "report"), ";\n\n");
    out.append("fn run_all() -> i32 {\n    var cases: goosetest::CaseResult[>..] = [];\n");
    out.append("    var failures: goosetest::Failure[>..] = [];\n    var diagnostics: u8[>..] = [];\n");
    out.append("    var metadata: u8[>..] = [];\n    let limits = goosetest::Limits {\n");
    format(out, "        cases: ", manifest.cases.len, ",\n        metadata_bytes: ",
        metadata_size(manifest, fail_fast), ",\n        ..\n    };\n");
    out.append("    var results = goosetest::new_results(cases, failures, diagnostics, metadata, limits);\n");
    if fail_fast {
        out.append("    results.fail_fast = true;\n");
    }
    out.append("    var t = goosetest::Test {\n        results: results,\n        ..\n    };\n");
    format(out, "    goosetest_generated_", child, "::run(t);\n");
    format(out, "    goosetest_generated_report::report(results, ", selected, ");\n");
    format(out, "    return goosetest_generated_completion::finish(goosetest::run_status(results), \"",
        completion_path(manifest), "\");\n}\n");
    add_module(output, generated_module_path(manifest, "runner.goose"), out);
}

fn metadata_size(manifest: discovery::Manifest&, fail_fast: bool = false) -> i64 {
    var total: i64 = 0;
    let target_prefix = if manifest.target_name.length > 0 {
        manifest.target_name.length + 2
    } else {
        0
    };
    for entry in manifest.cases {
        let suite = manifest.suites[entry.suite_index];
        total += suite.path.length + target_prefix + suite.namespace_name.length + entry.name.length
            + entry.display_name.length;
        if entry.disabled {
            total += entry.disabled_reason.length;
        } else if suite.before_all.present {
            total += "suite setup failed".len;
        } else if fail_fast {
            total += "fail-fast".len;
        }
    }
    for suite in manifest.suites {
        if suite.before_all.present {
            total += suite.path.length + target_prefix + suite.namespace_name.length + "before_all".len;
        }
        if suite.after_all.present {
            total += suite.path.length + target_prefix + suite.namespace_name.length + "after_all".len;
        }
    }
    return total;
}
