// Suite hooks surround contiguous case wrappers without introducing shared fixtures.
namespace generation;

import std;

import src.discovery.manifest;

fn has_suite_hooks(suite: discovery::Suite) -> bool {
    return suite.before_all.present || suite.after_all.present;
}

fn emit_suite_wrapper(out: u8[>..]&, manifest: discovery::Manifest&, index: i64, executable: bool) {
    let entry = manifest.cases[index];
    let suite = manifest.suites[entry.suite_index];
    let first = index == suite.first_case;
    let last = index + 1 == suite.first_case + suite.case_count;
    out.append("fn run(t: goosetest::Test&) {\n");
    if !executable {
        emit_disabled_suite(out, suite, first, last);
        return;
    }
    if first {
        out.append("    if t.results.incomplete {\n        return;\n    }\n");
        out.append("    t.suite_active = true;\n    t.suite_ready = true;\n");
        if suite.before_all.present {
            out.append("    t.suite_ready = before_suite(t);\n");
        }
    }
    out.append("    if !t.suite_active {\n        return;\n    }\n    run_selected(t);\n");
    if last {
        if suite.after_all.present {
            out.append("    after_suite(t);\n");
        }
        out.append("    t.suite_active = false;\n    t.suite_ready = true;\n");
    }
    out.append("}\n\n");
}

// Keep hook calls checked even when the suite has no executable cases.
fn emit_disabled_suite(out: u8[>..]&, suite: discovery::Suite, first: bool, last: bool) {
    if first && suite.before_all.present {
        out.append("    if false {\n        before_suite(t);\n    }\n");
    }
    out.append("    run_selected(t);\n");
    if last && suite.after_all.present {
        out.append("    if false {\n        after_suite(t);\n    }\n");
    }
    out.append("}\n\n");
}

fn emit_suite_helpers(out: u8[>..]&, manifest: discovery::Manifest&, index: i64) {
    let entry = manifest.cases[index];
    let suite = manifest.suites[entry.suite_index];
    let namespace_name = discovery::manifest_text(manifest, suite.namespace_name);
    if index == suite.first_case && suite.before_all.present {
        emit_suite_hook(out, namespace_name, suite.before_all, true);
    }
    if index + 1 == suite.first_case + suite.case_count && suite.after_all.present {
        emit_suite_hook(out, namespace_name, suite.after_all, false);
    }
}

fn emit_suite_hook(out: u8[>..]&, namespace_name: u8[:], hook: discovery::Hook, setup: bool) {
    let name = if setup {
        "before_all"
    } else {
        "after_all"
    };
    let helper = if setup {
        "before_suite"
    } else {
        "after_suite"
    };
    let phase = if setup {
        "SuiteSetup"
    } else {
        "SuiteCleanup"
    };
    format(out, "fn ", helper, "(t: goosetest::Test&)");
    if setup {
        out.append(" -> bool");
    }
    out.append(" {\n    let path = source_path();\n    let namespace_name = source_namespace();\n");
    out.append("    let identity = goosetest::CaseIdentity {\n        test_path: path,\n");
    out.append("        namespace_name: namespace_name,\n");
    format(out, "        function_name: \"", name, "\",\n        declaration_line: ", hook.location.line, ",\n");
    out.append("        ..\n    };\n    ");
    if setup {
        out.append("let ready = ");
    }
    format(out, "goosetest::run_suite_hook(t, identity, goosetest::Phase.", phase, ") {\n");
    format(out, "        ", namespace_name, "::", name, "(");
    if hook.uses_context {
        out.append("t");
    }
    out.append(");\n    }");
    if setup {
        out.append(";\n    return ready;");
    }
    out.append("\n}\n\n");
}
