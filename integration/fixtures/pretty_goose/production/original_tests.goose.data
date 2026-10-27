// Regression tests for Goose grammar-sensitive formatting and diagnostics.

import os;
import std;

import config;
import formatter;
import lexer;
import linter;

fn formatted(source: const u8[:]) -> u8[>..] {
    return formatter::format_source(source, formatter::FormatConfig {
            indent_width: 4,
            final_newline: true
        });
}

fn code_tokens(source: const u8[:]) -> lexer::Token[>..] {
    let tokens = lexer::lex(source);
    let imports, namespace_end, first_declaration = formatter::scan_imports(tokens);
    var result: lexer::Token[>..] = [];
    var i: i64 = 0;
    var entry: i64 = 0;
    while i < tokens.len {
        if entry < imports.len && i == imports[entry].first {
            i = imports[entry].last + 1;
            entry += 1;
            continue;
        }
        if tokens[i].kind != lexer::NEWLINE && tokens[i].kind != lexer::COMMENT {
            result.push(tokens[i]);
        }
        i += 1;
    }
    return result;
}

fn assert_tokens_preserved(source: const u8[:], actual: const u8[:]) {
    let before = code_tokens(source);
    let after = code_tokens(actual);
    assert(before.len == after.len);
    for i in before.len {
        assert(before[i].text == after[i].text);
        assert(before[i].kind == after[i].kind);
    }
}

fn expect_format(source: const u8[:], expected: const u8[:]) {
    let actual = formatted(source);
    if actual != expected {
        print("Unexpected format:\n", actual, "Expected:\n", expected);
    }
    assert(actual == expected);
    let second = formatted(actual);
    assert(second == actual);
    assert_tokens_preserved(source, actual);
}

fn expect_fragment(source: const u8[:], fragment: const u8[:]) {
    let actual = formatted(source);
    if find(actual, fragment) < 0 {
        print("Missing fragment: ", fragment, "\n", actual);
    }
    assert(find(actual, fragment) >= 0);
    let second = formatted(actual);
    assert(second == actual);
    assert_tokens_preserved(source, actual);
}

fn count_rule(source: const u8[:], rule: i32, options: config::Options) -> i64 {
    let issues = linter::lint(source, options);
    var count: i64 = 0;
    for issue in issues {
        if issue.rule == rule {
            count += 1;
        }
    }
    return count;
}

fn expect_rule(source: const u8[:], rule: i32, expected: i64) {
    let actual = count_rule(source, rule, config::defaults());
    if actual != expected {
        print("Rule ", rule, ": expected ", expected, ", got ", actual, "\n", source, "\n");
    }
    assert(actual == expected);
}

fn test_statement_blocks() {
    expect_format("fn f(){let v,ok=parse_int(s);for x,i in xs{return x,i,1;}}",
        "fn f() {\n    let v, ok = parse_int(s);\n    for x, i in xs {\n        return x, i, 1;\n    }\n}\n");
    expect_fragment("fn f(){if ok{return 1,2;}else if other{return 3,4;}else{return 5,6;}}",
        "} else if other {");
    expect_fragment("fn f(){guard ok else{return 1,2;}while ok {return 3,4;}loop{break;}}", "return 3, 4;");
    expect_fragment("struct Pair{a:i32,b:i32}", "    a: i32,\n    b: i32");
    expect_fragment("fn f(){let p=Pair{a:1,b:2};}", "        a: 1,\n        b: 2");
    expect_fragment("fn f(){match p {A=>1,B=>2,}}", "        A => 1,\n        B => 2,");
}

fn test_references_and_angles() {
    expect_fragment("fn f(){for & x in xs {use(& d.slots[i].val);}}", "for &x in xs {");
    expect_fragment("fn f(){use(& d.slots[i].val);}", "use(&d.slots[i].val);");
    expect_fragment("fn f(){match x {Rect & r=>{use(r);}}}", "Rect &r => {");
    expect_fragment("fn f(){use(a+&b,!&x,xs[^ 2..],xs[..^ 1]);}", "use(a + &b, !&x, xs[^2..], xs[..^1]);");
    expect_fragment("fn f(){let n:Node&<u32 in pool>?=nil;}", "Node&<u32 in pool>?");
    expect_fragment("fn f(){const for <N,A> in fields<T>{use(N,A);}}", "const for <N, A> in fields<T>");
    expect_format("type Int2=Vec2<i32>;", "type Int2 = Vec2<i32>;\n");
    expect_format("type Int2 = Vec2 < i32 >;", "type Int2 = Vec2<i32>;\n");
    expect_fragment("struct Box{v:Vec2<f32>}", "v: Vec2<f32>\n");
    expect_fragment("fn f(a:Vec<i32>[:],b:const u8[:][>..]){}", "a: Vec<i32>[:], b: const u8[:][>..]");
    expect_rule("fn f() {\n    for &x in xs {\n        use(&x, xs[^2..]);\n    }\n}\n", 2, 0);
    expect_rule("type Ref = Node&<u32 in pool>?;\n", 2, 0);
}

fn test_modifiers() {
    expect_rule("fn f(_ : i32){let value, _ = parse_int(s);}\n", 11, 0);
    expect_fragment("fn a(){} /* comment */ fn b(){}", "/* comment */\n\nfn b()");
    expect_fragment("fn outer(){fn a(){}fn b(){}}", "    }\n\n    fn b()");
    expect_fragment("fn a(){}export extern \"C\" fn b();", "}\n\nexport extern \"C\" fn b();");
    expect_fragment("export fn a(){}checkfree inline fn b(){}simd fn c(){}thread_fn fn d(){}",
        "}\n\ncheckfree inline fn b()");
    expect_format("reusable[] var slots:u8[>..]=[];", "reusable[] var slots: u8[>..] = [];\n");
    expect_rule("export checkfree inline fn badName() {}\n", 11, 1);
    expect_rule("reusable[] var badName: u8[>..] = [];\n", 11, 1);
    expect_rule("thread_fn fn f(a:i32,b:i32,c:i32,d:i32,e:i32,f:i32,g:i32){}\n", 8, 1);
    expect_rule("inline fn f(a:i32,b:i32,c:i32,d:i32,e:i32,f:i32,){}\n", 8, 0);
    expect_rule("checkfree fn f() -> i32, i32, i32, i32 {}\n", 9, 1);
    expect_rule("export fn f\n(a:i32,b:i32,c:i32,d:i32,e:i32,f:i32,g:i32){}\n", 8, 1);
}

fn test_imports() {
    expect_format("namespace demo; import std; import os; fn f(){return 1,2;}",
        "namespace demo;\n\nimport os;\nimport std;\n\nfn f() {\n    return 1, 2;\n}\n");
    expect_format("namespace demo;\nimport z;\nimport std;\nimport lib\nfrom \"url\";\n",
        "namespace demo;\n\nimport lib from \"url\";\n\nimport std;\n\nimport z;\n");
    expect_format("// header\nnamespace demo; // ns\n\n// local\nimport z; // z\n// standard\nimport std; // std\n",
        "// header\nnamespace demo; // ns\n\n// standard\nimport std; // std\n\n// local\nimport z; // z\n");
    expect_format("fn f(){}\nimport z;\nimport binary;\n", "import binary;\n\nimport z;\n\nfn f() {\n}\n");
    expect_rule("namespace demo;\n\nimport binary;\nimport std;\n\nimport a.b;\nimport a.c;\n", 12, 0);
    expect_rule("import std;\nimport os;\n", 12, 1);
    expect_rule("import std;\nimport std;\n", 12, 1);
    expect_rule("fn f(){}\nimport std;\n", 12, 1);
    expect_rule("import std;\nnamespace demo;\n", 12, 1);
    expect_rule("import std;\nimport project;\n", 12, 1);
    expect_rule("import a.b;\nimport a.c;\n", 12, 0);
    expect_rule("import a from \"one\";\nimport a from \"two\";\n", 12, 0);
}

fn test_parens_and_constants() {
    expect_rule("fn f(){if(x){}while(x){}for(x in xs){}guard(x)else{}match(x){}return(x);}\n", 13, 6);
    expect_rule("fn f(){if (x) && y {}while ready(x) {}return (x) + y;}\n", 13, 0);
    expect_rule("const bad_name = 1;\nconst GOOD_NAME: i32 = 2;\n", 16, 1);
    expect_rule("const bad_name, OTHER = pair();\n", 16, 1);
    expect_rule("fn f<const n:i32>(){const local=1;}\n", 16, 0);
    expect_rule("extern fn f(data:u8[:],other:const u8[:]);\n", 15, 1);
    expect_rule("extern fn f(callback:fn(data:u8[:])->i32);\n", 15, 0);
    expect_rule("fn f(data:u8[:]){}\n", 15, 0);
}

fn test_reference_bindings() {
    expect_rule("fn f(){let n=pool.push(Node{});n.value=1;}\n", 17, 1);
    expect_rule("fn f(){var n=pool.alloc_ref(Node{});root.next .= n;}\n", 17, 1);
    expect_rule("fn f(){let n=pool.push(Node{});links[i] .= n;}\n", 17, 1);
    expect_rule("fn f(){let n.=pool.push(Node{});n.value=1;}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});use(n.value);}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});root.value=n.value;}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});{let n=other;n.value=1;}}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});{let n=other;n.value=1;}n.value=2;}\n", 17, 1);
    expect_rule("fn f(){let n=pool.push(Node{});for n in xs {n.value=1;}}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});n=other;n.value=1;}\n", 17, 0);
    expect_rule("fn f(){let n=wrap(pool.push(Node{}));n.value=1;}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{}).value;n.value=1;}\n", 17, 0);
    expect_rule("fn f(){let n=pool.push(Node{});other.n.value=1;}\n", 17, 0);
    expect_rule("struct Node{data:u8[>..]} fn f(){let n=pool.push(Node{});n.data[0]=1;}\n", 17, 0);
    expect_rule("struct Node{data:u8[..16]} fn f(){let n=pool.push(Node{});n.data[0]=1;}\n", 17, 1);
}

fn test_assertions_and_loops() {
    expect_rule("fn f(){assert(a&&b);assert((a&&b));assert(a&&(b||c));}\n", 18, 3);
    expect_rule("fn f(){assert(valid(a&&b));assert((a&&b)||c);assert(a);}\n", 18, 0);
    expect_rule("fn f(){loop{}while true{}while(true){}}\n", 19, 3);
    expect_rule("fn f(){while true&&ready{}while ready{}loop{if done{break;}}}\n", 19, 0);
    expect_rule("fn f(){loop{for i in 10{break;}}}\n", 19, 1);
    expect_rule("fn f(){loop{for i in 10{return;}}}\n", 19, 0);
    expect_rule("fn f(){loop{fn g(){return;}}}\n", 19, 1);
    expect_rule("fn f(){loop{let abort=false;}}\n", 19, 1);
    expect_rule("fn f(){loop{abort();}}\n", 19, 0);
    expect_rule("fn f(){loop{assert(step<MAX_STEPS);step+=1;}}\n", 19, 0);
    expect_rule("fn f(){loop{step+=1;}}\n", 19, 1);
    expect_rule("fn f(){loop{fn check(){assert(step<MAX);}step+=1;}}\n", 19, 1);
    var strict = config::defaults();
    strict.strict_safety = true;
    assert(count_rule("recursive fn f(){}\n", 19, strict) == 1);
    expect_rule("recursive fn f(){}\n", 19, 0);
}

fn test_limits_and_configuration() {
    var source: u8[>..] = [];
    source.append("fn f(){\n");
    for _ in 68 {
        source.append("// line\n");
    }
    let at_limit = str(source, "}\n");
    expect_rule(at_limit, 14, 0);
    source.append("// line\n}\n");
    expect_rule(source, 14, 1);
    var options = config::defaults();
    assert(config::set_integer(options, "lint", "max_function_lines", "71") == "");
    assert(count_rule(source, 14, options) == 0);
    assert(config::set_boolean(options, "lint", "function_length", "false") == "");
    options.max_function_lines = 1;
    assert(count_rule(source, 14, options) == 0);
    assert(config::set_boolean(options, "lint", "split_compound_assert", "false") == "");
    assert(count_rule("fn f(){assert(a&&b);}", 18, options) == 0);
}

fn test_literal_preservation() {
    let source = "fn f(){use(\"a, { b }\",'\\n');/* outer /* nested */ x */let x=1.2e-3;}\n";
    let actual = formatted(source);
    let before = lexer::lex(source);
    let after = lexer::lex(actual);
    var next: i64 = 0;
    for token in before {
        if token.kind == lexer::NEWLINE {
            continue;
        }
        while next < after.len && after[next].kind == lexer::NEWLINE {
            next += 1;
        }
        assert(next < after.len);
        assert(token.text == after[next].text);
        assert(token.kind == after[next].kind);
        next += 1;
    }
}

fn test_corpus_file(path: const u8[:]) {
    var source: u8[>..] = [];
    assert(read_file(path, source));
    let actual = formatted(source);
    let second = formatted(actual);
    if second != actual {
        print("Unstable formatting: ", path, "\n");
    }
    assert(second == actual);
    assert_tokens_preserved(source, actual);
}

fn main() {
    test_statement_blocks();
    test_references_and_angles();
    test_modifiers();
    test_imports();
    test_parens_and_constants();
    test_reference_bindings();
    test_assertions_and_loops();
    test_limits_and_configuration();
    test_literal_preservation();
    let argv = args();
    for i in 1..argv.len {
        test_corpus_file(argv[i]);
    }
    print("goosefmt regression tests passed\n");
}
