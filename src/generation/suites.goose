// One bounded case module preserves direct calls and original-source metadata.
namespace generation;

import std;

import src.discovery.manifest;
import src.generation.literals;
import src.generation.model;
import src.generation.validation;

fn emit_case(output: Output&, manifest: discovery::Manifest&, index: i64) {
    let entry = manifest.cases[index];
    let suite = manifest.suites[entry.suite_index];
    let path = discovery::manifest_text(manifest, suite.path);
    let namespace_name = discovery::manifest_text(manifest, suite.namespace_name);
    let function_name = discovery::manifest_text(manifest, entry.name);
    var out: u8[>..] = [];
    format(out, "// Generated direct case wrapper; edit the original test source.\nnamespace goosetest_generated_case_",
        index, ";\n\nimport goosetest;\n\nimport ", import_path(path), ";\n\n");
    out.append("fn run(t: goosetest::Test&) {\n    if t.results.incomplete {\n        return;\n    }\n");
    out.append("    let path = source_path();\n    let namespace_name = source_namespace();\n");
    out.append("    let function_name = source_function();\n    let display_name = source_display();\n");
    out.append("    let identity = goosetest::CaseIdentity {\n        test_path: path,\n");
    out.append("        namespace_name: namespace_name,\n        function_name: function_name,\n");
    format(out, "        display_name: display_name,\n        declaration_line: ", entry.location.line, ",\n    };\n");
    format(out, "    goosetest::execute_case(t, identity) {\n        ",
        namespace_name, "::", function_name, "(t);\n    }\n}\n\n");
    emit_text(out, "source_path", path);
    emit_text(out, "source_namespace", namespace_name);
    emit_text(out, "source_function", function_name);
    emit_text(out, "source_display", discovery::manifest_text(manifest, entry.display_name));
    add_module(output, str("case_", index, ".goose"), out);
}
