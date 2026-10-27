import std;
import os;

// ============================================================================
// goosetest: JUnit-Style Mirror Discovery & Runner Generator (Pure Goose)
// ============================================================================
// Enforces the project convention:
//   ./src/<dir>/<module>.goose   <--->   ./test/<dir>/<module>_test.goose
//
// 1. Walks `./src` and `./test` iteratively (0 recursion, fixed path buffers)
// 2. Audits 1:1 file-tree mirroring (reports covered modules, missing test
//    mirrors, and orphaned test files)
// 3. Scans each `test/**/*_test.goose` for:
//      - `namespace <ns>;`
//      - `struct Fixture`
//      - `fn before_all()`, `fn before_each(...)`, `fn after_each(...)`, `fn after_all()`
//      - `fn test_*(...)` + JUnit doc annotations (`@DisplayName`, `@Disabled`, `@RepeatedTest`)
// 4. Emits `<project_root>/.goosetest_runner.goose` for whole-program execution

struct Span {
    off: i64,
    len: i64,
}

struct DiscoveredCase {
    fn_name: Span,
    display_name: Span,
    disabled_reason: Span,
    repeats: i64 = 1,
}

// Iteratively walks relative `.goose` file paths under `root_dir` into `text_pool`
fn walk_goose_files(
    root_dir: const u8[:],
    text_pool: u8[>..]&,
    spans: Span[..128]&
) {
    var dir_pool: u8[>..] = [];
    var dir_stack: Span[..64] = [];
    dir_stack.push(Span { off: 0, len: 0 }); // start at ""

    while dir_stack.len > 0 {
        let cur = dir_stack.pop();
        let sub_rel = dir_pool[cur.off..cur.off + cur.len];

        var full_path: u8[..512] = [];
        full_path.append(root_dir);
        if sub_rel.len > 0 {
            full_path.push('/');
            full_path.append(sub_rel);
        }

        var entries: u8[>..] = [];
        if !list_dir(full_path, entries) { continue; }

        var pos = 0;
        while pos < entries.len {
            var nl = pos;
            while nl < entries.len && entries[nl] != '\n' { nl += 1; }
            let name = entries[pos..nl];
            pos = nl + 1;
            if name.len == 0 || name[0] == '.' { continue; }

            var child_rel: u8[..512] = [];
            if sub_rel.len > 0 {
                child_rel.append(sub_rel);
                child_rel.push('/');
            }
            child_rel.append(name);

            var child_full: u8[..512] = [];
            child_full.append(root_dir);
            child_full.push('/');
            child_full.append(child_rel);

            if is_dir(child_full) {
                if dir_stack.len < dir_stack.cap {
                    let d_off = dir_pool.len;
                    dir_pool.append(child_rel);
                    dir_stack.push(Span { off: d_off, len: child_rel.len });
                }
            } else if ends_with(name, ".goose") && spans.len < spans.cap {
                let f_off = text_pool.len;
                text_pool.append(child_rel);
                spans.push(Span { off: f_off, len: child_rel.len });
            }
        }
    }
}

fn extract_quoted(line: const u8[:], tag: const u8[:], empty: const u8[:]) -> const u8[:] {
    let idx = find(line, tag);
    guard idx >= 0 else { return empty; }
    let rest = line[idx + tag.len..];
    let q1 = find(rest, "\"");
    guard q1 >= 0 else { return empty; }
    let after_q1 = rest[q1 + 1..];
    let q2 = find(after_q1, "\"");
    guard q2 >= 0 else { return empty; }
    return after_q1[..q2];
}

fn extract_int_arg(line: const u8[:], tag: const u8[:]) -> i64 {
    let idx = find(line, tag);
    guard idx >= 0 else { return 1; }
    let rest = line[idx + tag.len..];
    let p1 = find(rest, "(");
    guard p1 >= 0 else { return 1; }
    let after_p1 = rest[p1 + 1..];
    let p2 = find(after_p1, ")");
    guard p2 > 0 else { return 1; }
    let v, ok = parse_int(trim(after_p1[..p2]));
    return if ok && v > 0 { v } else { 1 };
}

// Convert "auth/token_test.goose" -> "test.auth.token_test"
fn format_import_dot_path(out: u8[>..]&, prefix: const u8[:], rel_goose: const u8[:]) {
    out.append(prefix);
    out.push('.');
    let stem = rel_goose[..rel_goose.len - 6]; // strip ".goose"
    for c in stem {
        if c == '/' { out.push('.'); } else { out.push(c); }
    }
}

fn scan_and_emit_suite(
    project_root: const u8[:],
    src_rel: const u8[:],
    test_rel: const u8[:],
    imports_out: u8[>..]&,
    calls_out: u8[>..]&
) {
    var test_full: u8[>..] = [];
    format(test_full, project_root, "/test/", test_rel);

    var source: u8[>..] = [];
    guard read_file(test_full, source) else { return; }
    guard source.len > 0 else { return; }

    // 1. Emit `import test.<path>;`
    imports_out.append("import ");
    format_import_dot_path(imports_out, "test", test_rel);
    imports_out.append(";\n");

    // 2. Scan declarations & JUnit annotations in `source`
    let empty_src: const u8[:] = source[0..0];
    var ns_name: const u8[:] = empty_src;
    var has_fixture = false;
    var has_before_all = false;
    var has_after_all = false;
    var has_before_each = false;
    var has_after_each = false;

    var pending_display: const u8[:] = empty_src;
    var pending_disabled: const u8[:] = empty_src;
    var pending_repeats = 1;

    var case_pool: u8[>..] = [];
    var cases: DiscoveredCase[..64] = [];

    each_split(source, '\n') { raw_line =>
        let line = trim(raw_line);
        if starts_with(line, "namespace ") {
            let semi = find(line, ";");
            if semi > 10 { ns_name = trim(line[10..semi]); }
        } else if starts_with(line, "struct Fixture") {
            has_fixture = true;
        } else if starts_with(line, "//") {
            let disp = extract_quoted(line, "@DisplayName", empty_src);
            if disp.len > 0 { pending_display = disp; }
            let dis = extract_quoted(line, "@Disabled", empty_src);
            if dis.len > 0 { pending_disabled = dis; }
            if find(line, "@RepeatedTest") >= 0 {
                pending_repeats = extract_int_arg(line, "@RepeatedTest");
            }
        } else if starts_with(line, "fn ") {
            let rest = trim(line[3..]);
            let paren = find(rest, "(");
            if paren > 0 {
                let fn_name = trim(rest[..paren]);
                if fn_name == "before_all" { has_before_all = true; }
                else if fn_name == "after_all" { has_after_all = true; }
                else if fn_name == "before_each" { has_before_each = true; }
                else if fn_name == "after_each" { has_after_each = true; }
                else if starts_with(fn_name, "test_") && cases.len < cases.cap {
                    let fn_off = case_pool.len;
                    case_pool.append(fn_name);
                    let disp_off = case_pool.len;
                    case_pool.append(pending_display);
                    let dis_off = case_pool.len;
                    case_pool.append(pending_disabled);
                    cases.push(DiscoveredCase {
                        fn_name: Span { off: fn_off, len: fn_name.len },
                        display_name: Span { off: disp_off, len: pending_display.len },
                        disabled_reason: Span { off: dis_off, len: pending_disabled.len },
                        repeats: pending_repeats,
                    });
                }
            }
            pending_display = empty_src;
            pending_disabled = empty_src;
            pending_repeats = 1;
        } else if line.len > 0 {
            pending_display = empty_src;
            pending_disabled = empty_src;
            pending_repeats = 1;
        }
    };

    guard ns_name.len > 0 else { return; }

    // 3. Emit suite execution block into `calls_out`
    format(calls_out, "    t.begin_suite(\"", ns_name, "\", \"src/", src_rel, "\", \"test/", test_rel, "\");\n");
    if has_before_all {
        format(calls_out, "    ", ns_name, "::before_all();\n");
    }

    for c in cases {
        let fn_str = case_pool[c.fn_name.off..c.fn_name.off + c.fn_name.len];
        let disp_str = case_pool[c.display_name.off..c.display_name.off + c.display_name.len];
        let dis_str = case_pool[c.disabled_reason.off..c.disabled_reason.off + c.disabled_reason.len];

        if dis_str.len > 0 {
            // Keep disabled test in `run_case` call graph so Goose typechecks it
            // (preventing bit-rot!) and satisfies §20 `return from run_case` check:
            format(calls_out, "    if false {\n");
            if has_fixture {
                format(calls_out, "        var f = ", ns_name, "::Fixture { .. };\n");
                format(calls_out, "        run_case(t) { ", ns_name, "::", fn_str, "(t, f); };\n");
            } else {
                format(calls_out, "        run_case(t) { ", ns_name, "::", fn_str, "(t); };\n");
            }
            format(calls_out, "    }\n");
            format(calls_out, "    t.skip_case(\"", fn_str, "\", \"", disp_str, "\", \"", dis_str, "\");\n");
        } else {
            format(calls_out, "    t.begin_case(\"", fn_str, "\", \"", disp_str, "\");\n");
            format(calls_out, "    for rep in ", c.repeats, " {\n");
            if has_fixture {
                format(calls_out, "        var f = ", ns_name, "::Fixture { .. };\n");
            }
            if has_before_each && has_fixture {
                format(calls_out, "        ", ns_name, "::before_each(f);\n");
            }
            format(calls_out, "        run_case(t) {\n");
            if has_fixture {
                format(calls_out, "            ", ns_name, "::", fn_str, "(t, f);\n");
            } else {
                format(calls_out, "            ", ns_name, "::", fn_str, "(t);\n");
            }
            format(calls_out, "        };\n");
            if has_after_each && has_fixture {
                format(calls_out, "        ", ns_name, "::after_each(f);\n");
            }
            format(calls_out, "        if t.failed { break; }\n");
            format(calls_out, "    }\n");
            format(calls_out, "    t.end_case(", c.repeats, ");\n");
        }
    }

    if has_after_all {
        format(calls_out, "    ", ns_name, "::after_all();\n");
    }
    calls_out.append("    t.end_suite();\n\n");
}

fn generate_junit_runner(project_root: const u8[:]) -> bool {
    var src_dir: u8[>..] = [];
    format(src_dir, project_root, "/src");
    var test_dir: u8[>..] = [];
    format(test_dir, project_root, "/test");

    var src_pool: u8[>..] = [];
    var src_spans: Span[..128] = [];
    walk_goose_files(src_dir, src_pool, src_spans);

    var test_pool: u8[>..] = [];
    var test_spans: Span[..128] = [];
    walk_goose_files(test_dir, test_pool, test_spans);

    print("═══════════════════ goosetest Mirror Audit ═════════════════════");
    var mirrored_count = 0;
    var missing_count = 0;

    var imports_buf: u8[>..] = [];
    var calls_buf: u8[>..] = [];

    for sp in src_spans {
        let src_rel = src_pool[sp.off..sp.off + sp.len];
        let stem = src_rel[..src_rel.len - 6]; // strip ".goose"
        var expected_test_rel: u8[>..] = [];
        format(expected_test_rel, stem, "_test.goose");

        var found = false;
        for tp in test_spans {
            let t_rel = test_pool[tp.off..tp.off + tp.len];
            if t_rel == expected_test_rel {
                found = true;
                break;
            }
        }

        if found {
            mirrored_count += 1;
            print("  [MIRROR OK]      src/", src_rel, "  <-->  test/", expected_test_rel);
            scan_and_emit_suite(project_root, src_rel, expected_test_rel, imports_buf, calls_buf);
        } else {
            missing_count += 1;
            print("  [MISSING TEST]   src/", src_rel, "  (expected test/", expected_test_rel, ")");
        }
    }

    for tp in test_spans {
        let t_rel = test_pool[tp.off..tp.off + tp.len];
        if !ends_with(t_rel, "_test.goose") {
            print("  [NAMING WARN]    test/", t_rel, "  (test files should end with _test.goose)");
            continue;
        }
        let stem = t_rel[..t_rel.len - 11]; // strip "_test.goose"
        var expected_src_rel: u8[>..] = [];
        format(expected_src_rel, stem, ".goose");
        var has_src = false;
        for sp in src_spans {
            if src_pool[sp.off..sp.off + sp.len] == expected_src_rel {
                has_src = true;
                break;
            }
        }
        if !has_src {
            print("  [ORPHAN TEST]    test/", t_rel, "  (no matching src/", expected_src_rel, ")");
        }
    }
    print("Mirror Coverage: ", mirrored_count, "/", src_spans.len, " source modules have mirrored tests\n");

    var runner_code: u8[>..] = [];
    runner_code.append("// AUTO-GENERATED BY goosetest — DO NOT EDIT\n");
    runner_code.append("import std;\n");
    runner_code.append("import goosetest;\n");
    runner_code.append(imports_buf);
    runner_code.append("\nfn main() {\n");
    runner_code.append("    var t = new_runner();\n\n");
    runner_code.append(calls_buf);
    runner_code.append("    let code = t.summary();\n");
    runner_code.append("}\n");

    var out_path: u8[>..] = [];
    format(out_path, project_root, "/.goosetest_runner.goose");
    return write_file(out_path, runner_code);
}

fn main() {
    let project = "/Users/bob/repos/goosetest/docs/example_project";
    let ok = generate_junit_runner(project);
    assert(ok);
}
