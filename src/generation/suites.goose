// One bounded case module preserves direct calls and original-source metadata.
namespace generation;

import std;

import src.discovery.manifest;
import src.generation.literals;
import src.generation.model;
import src.generation.suite_hooks;
import src.generation.validation;

fn emit_case(output: Output&, manifest: discovery::Manifest&, index: i64, executable: bool, selected: bool) {
    let entry = manifest.cases[index];
    let suite = manifest.suites[entry.suite_index];
    let path = discovery::manifest_text(manifest, suite.path);
    let namespace_name = discovery::manifest_text(manifest, suite.namespace_name);
    let function_name = discovery::manifest_text(manifest, entry.name);
    var out: u8[>..] = [];
    format(out, "// Generated direct case wrapper; edit the original test source.\nnamespace goosetest_generated_case_",
        index, ";\n\nimport goosetest;\n\nimport ", import_path(path), ";\n\n");
    if has_suite_hooks(suite) {
        emit_suite_wrapper(out, manifest, index, executable);
        out.append("fn run_selected(t: goosetest::Test&) {\n");
    } else {
        out.append("fn run(t: goosetest::Test&) {\n");
    }
    if !selected {
        emit_filtered(out);
    }
    out.append("    if t.results.incomplete {\n        return;\n    }\n");
    out.append("    let path = source_path();\n    let namespace_name = source_namespace();\n");
    out.append("    let function_name = source_function();\n    let display_name = source_display();\n");
    out.append("    let identity = goosetest::CaseIdentity {\n        test_path: path,\n");
    out.append("        namespace_name: namespace_name,\n        function_name: function_name,\n");
    format(out, "        display_name: display_name,\n        declaration_line: ", entry.location.line, ",\n    };\n");
    if entry.disabled {
        emit_disabled_skip(out);
    } else if has_suite_hooks(suite) {
        out.append("    if !t.suite_ready {\n");
        out.append("        goosetest::skip_case(t.results, identity, \"suite setup failed\");\n");
        out.append("        return;\n    }\n");
    }
    if !entry.disabled {
        emit_fail_fast(out);
    }
    if entry.uses_fixture {
        emit_fixture(out, namespace_name, function_name, suite);
    } else {
        format(out, "    goosetest::execute_case(t, identity) {\n        ",
            namespace_name, "::", function_name, "(t);\n    }\n}\n\n");
    }
    emit_suite_helpers(out, manifest, index);
    emit_text(out, "source_path", path);
    emit_text(out, "source_namespace", namespace_name);
    emit_text(out, "source_function", function_name);
    emit_text(out, "source_display", discovery::manifest_text(manifest, entry.display_name));
    if entry.disabled {
        emit_text(out, "source_reason", discovery::manifest_text(manifest, entry.disabled_reason));
    }
    add_module(output, str("case_", index, ".goose"), out);
}

// Preserve the whole unselected call path, but retain no executed/skipped record.
fn emit_filtered(out: u8[>..]&) {
    out.append("    if false {\n        run_unselected(t);\n    }\n");
    out.append("    goosetest::record_filtered(t.results);\n}\n\n");
    out.append("fn run_unselected(t: goosetest::Test&) {\n");
}

fn emit_fail_fast(out: u8[>..]&) {
    out.append("    if t.results.fail_fast_stop {\n");
    out.append("        goosetest::not_run_case(t.results, identity, \"fail-fast\");\n");
    out.append("        return;\n    }\n");
}

// The pinned compiler specializes calls in `if false` before dead-code elimination.
fn emit_disabled_skip(out: u8[>..]&) {
    out.append("    if false {\n        run_disabled(t, identity);\n    }\n");
    out.append("    let reason = source_reason();\n    goosetest::skip_case(t.results, identity, reason);\n}\n\n");
    out.append("fn run_disabled(t: goosetest::Test&, identity: goosetest::CaseIdentity) {\n");
}

fn emit_fixture(out: u8[>..]&, namespace_name: u8[:], function_name: u8[:], suite: discovery::Suite) {
    out.append("    goosetest::execute_fixture(t, identity) {\n");
    format(out, "        var fixture = ", namespace_name, "::Fixture {\n            ..\n        };\n");
    if suite.before_each.present {
        emit_each_hook(out, namespace_name, "before_each", "Setup", suite.before_each.uses_context);
    }
    out.append("        if t.failures == 0 && !t.results.incomplete {\n");
    out.append("            goosetest::run_phase(t, goosetest::Phase.Body) {\n");
    if namespace_name.len + function_name.len > 89 {
        format(out, "                ", namespace_name, "::", function_name, "(\n");
        out.append("                    t, fixture\n                );\n");
    } else {
        format(out, "                ", namespace_name, "::", function_name, "(t, fixture);\n");
    }
    out.append("            }\n        }\n");
    if suite.after_each.present {
        emit_each_hook(out, namespace_name, "after_each", "Cleanup", suite.after_each.uses_context);
    }
    out.append("    }\n}\n\n");
}

fn emit_each_hook(out: u8[>..]&, namespace_name: u8[:], name: u8[:], phase: u8[:], context: bool) {
    format(out, "        goosetest::run_phase(t, goosetest::Phase.", phase, ") {\n");
    format(out, "            ", namespace_name, "::", name, "(");
    if context {
        out.append("t, ");
    }
    out.append("fixture);\n        }\n");
}
