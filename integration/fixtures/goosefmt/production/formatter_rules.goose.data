// Token-context helpers shared by Goose formatting and lint rules.
namespace formatter;

import lexer;

let BLOCK_STATEMENT: i32 = 1;
let BLOCK_LAYOUT: i32 = 2;

fn previous_significant(tokens: lexer::Token[:], index: i64) -> i64 {
    var i = index - 1;
    while i >= 0 && (tokens[i].kind == lexer::NEWLINE || tokens[i].kind == lexer::COMMENT) {
        i -= 1;
    }
    return i;
}

fn next_significant(tokens: lexer::Token[:], index: i64) -> i64 {
    var i = index;
    while i < tokens.len && (tokens[i].kind == lexer::NEWLINE || tokens[i].kind == lexer::COMMENT) {
        i += 1;
    }
    return i;
}

fn has_trailing_comment(tokens: lexer::Token[:], index: i64) -> bool {
    return index + 1 < tokens.len && tokens[index + 1].kind == lexer::COMMENT
        && tokens[index + 1].line == tokens[index].end_line;
}

fn is_function_modifier(text: const u8[:]) -> bool {
    return text == "extern" || text == "export" || text == "recursive"
        || text == "checkfree" || text == "simd" || text == "inline"
        || text == "thread_fn";
}

fn is_type_reference(tokens: lexer::Token[:], index: i64) -> bool {
    if index == 0 {
        return false;
    }
    var back = index - 1;
    while back >= 0 && index - back <= 12 {
        let text = tokens[back].text;
        if text == ":" || text == "->" || text == "<" || text == "type" {
            return true;
        }
        if text == "=" && back >= 2 && tokens[back - 2].text == "type" {
            return true;
        }
        if text == "=" || text == ".=" || text == ";" || text == "{"
            || text == "}" || text == "return" || text == "=>"
            || text == "(" || text == ")" || text == "," || text == "for"
            || text == "in" {
            return false;
        }
        back -= 1;
    }
    return false;
}

fn is_array_bound(tokens: lexer::Token[:], index: i64, square_depth: i64) -> bool {
    let text = tokens[index].text;
    if text == ".." || text == "..=" {
        return true;
    }
    if square_depth == 0 {
        return false;
    }
    if text == ">" && index + 1 < tokens.len && tokens[index + 1].text == ".." {
        return true;
    }
    if text == "<" && index > 0 && tokens[index - 1].text == ".." {
        return true;
    }
    return false;
}

fn generic_close(tokens: lexer::Token[:], i: i64) -> i64 {
    var depth: i64 = 1;
    var j = i + 1;
    while j < tokens.len {
        if tokens[j].kind == lexer::NEWLINE || tokens[j].kind == lexer::COMMENT {
            j += 1;
            continue;
        }
        if tokens[j].text == "<" {
            depth += 1;
        }
        if tokens[j].text == ">" || tokens[j].text == ">>" {
            depth -= if tokens[j].text == ">>" {
                2
            } else {
                1
            };
            if depth <= 0 {
                return j;
            }
        }
        if depth == 1 && (tokens[j].text == ";" || tokens[j].text == "{" || tokens[j].text == "}") {
            break;
        }
        j += 1;
    }
    return -1;
}

fn generic_angles(tokens: lexer::Token[:]) -> bool[>..] {
    var marks: bool[>..] = [];
    for _ in tokens.len {
        marks.push(false);
    }
    for i in tokens.len {
        if tokens[i].text != "<" {
            continue;
        }
        let before = previous_significant(tokens, i);
        if before < 0 {
            continue;
        }

        var specialization = false;
        if tokens[before].text == "for" {
            let before_for = previous_significant(tokens, before);
            specialization = before_for >= 0 && tokens[before_for].text == "const";
        }
        let before_name = previous_significant(tokens, before);
        let declaration = before_name >= 0 && (tokens[before_name].text == "fn"
            || tokens[before_name].text == "struct" || tokens[before_name].text == "enum");
        if !specialization && !declaration && !is_type_reference(tokens, i)
            && tokens[before].text != "&" && tokens[before].end != tokens[i].start {
            continue;
        }
        if tokens[before].kind != lexer::IDENT && tokens[before].text != "&"
            && tokens[before].text != ">" && tokens[before].text != "]" {
            continue;
        }

        let close = generic_close(tokens, i);
        if close < 0 {
            continue;
        }
        let next = next_significant(tokens, close + 1);
        let followed_by_in = specialization && next < tokens.len && tokens[next].text == "in";
        if followed_by_in || next >= tokens.len || tokens[next].kind == lexer::NEWLINE
            || tokens[next].text == "(" || tokens[next].text == "{" || tokens[next].text == "}"
            || tokens[next].text == ";" || tokens[next].text == "." || tokens[next].text == ")"
            || tokens[next].text == "," || tokens[next].text == "]" || tokens[next].text == "["
            || tokens[next].text == "&" || tokens[next].text == "?" || tokens[next].text == "=" {
            marks[i] = true;
            marks[close] = true;
        }
    }
    return marks;
}

fn is_unary_context(tokens: lexer::Token[:], index: i64) -> bool {
    let text = tokens[index].text;
    if text == "!" || text == "~" {
        return true;
    }
    if text != "+" && text != "-" && text != "*" && text != "&" && text != "^" {
        return false;
    }
    let before = previous_significant(tokens, index);
    if before < 0 {
        return true;
    }
    let previous = tokens[before];
    if text == "&" {
        if previous.text == "for" || previous.text == "in" || previous.text == "return"
            || previous.text == "=" || previous.text == ".=" || previous.text == "("
            || previous.text == "[" || previous.text == "," || previous.text == ":"
            || previous.text == "=>" || previous.text == "&&" || previous.text == "||"
            || previous.text == "!" || previous.text == "~" || previous.text == "+"
            || previous.text == "-" || previous.text == "*" || previous.text == "/"
            || previous.text == "==" || previous.text == "!=" || previous.text == "if"
            || previous.text == "while" || previous.text == "guard" || previous.text == "match" {
            return true;
        }
        let after = next_significant(tokens, index + 1);
        let after_value = next_significant(tokens, after + 1);
        return previous.kind == lexer::IDENT && after < tokens.len
            && tokens[after].kind == lexer::IDENT
            && after_value < tokens.len && tokens[after_value].text == "=>";
    }
    if text == "^" {
        return previous.text == "[" || previous.text == ".." || previous.text == "..=";
    }
    if text == "*" && previous.end == tokens[index].start {
        return false;
    }
    return previous.text == "(" || previous.text == "[" || previous.text == "{"
        || previous.text == "," || previous.text == ":" || previous.text == "="
        || previous.text == ".=" || previous.text == "+" || previous.text == "-"
        || previous.text == "*" || previous.text == "/" || previous.text == "%"
        || previous.text == "==" || previous.text == "!=" || previous.text == "&&"
        || previous.text == "||" || previous.text == "=>" || previous.text == "->"
        || previous.text == "return" || previous.text == "in";
}

fn block_context(tokens: lexer::Token[:], open_index: i64) -> i32 {
    var nested_braces: i64 = 0;
    var parens: i64 = 0;
    var squares: i64 = 0;
    var i = open_index - 1;
    while i >= 0 {
        let token = tokens[i];
        let text = token.text;
        if token.kind == lexer::NEWLINE || token.kind == lexer::COMMENT {
            i -= 1;
            continue;
        }
        if text == "}" {
            nested_braces += 1;
        } else if text == "{" {
            if nested_braces == 0 {
                break;
            }
            nested_braces -= 1;
            if nested_braces == 0 {
                break;
            }
        } else if text == ")" {
            parens += 1;
        } else if text == "(" && parens > 0 {
            parens -= 1;
        } else if text == "]" {
            squares += 1;
        } else if text == "[" && squares > 0 {
            squares -= 1;
        }

        if nested_braces == 0 && parens == 0 && squares == 0 {
            if text == "=>" {
                return BLOCK_STATEMENT;
            }
            if text == "if" || text == "else" || text == "while" || text == "for"
                || text == "loop" || text == "guard" || text == "block" || text == "fn"
                || is_function_modifier(text) {
                return BLOCK_STATEMENT;
            }
            if text == "match" || text == "struct" || text == "enum" {
                return BLOCK_LAYOUT;
            }
            if text == ";" {
                break;
            }
        }
        i -= 1;
    }
    return BLOCK_LAYOUT;
}

fn function_declaration_start(tokens: lexer::Token[:], index: i64) -> i64 {
    var start = index;
    var previous = previous_significant(tokens, start);
    while previous >= 0 {
        if is_function_modifier(tokens[previous].text) {
            start = previous;
        } else if tokens[previous].kind == lexer::STRING {
            let modifier = previous_significant(tokens, previous);
            if modifier < 0 || tokens[modifier].text != "extern" {
                break;
            }
            start = modifier;
        } else {
            break;
        }
        previous = previous_significant(tokens, start);
    }
    var probe = start - 1;
    while probe >= 0 {
        while probe >= 0 && tokens[probe].kind == lexer::NEWLINE {
            probe -= 1;
        }
        if probe < 0 || tokens[probe].kind != lexer::COMMENT {
            break;
        }
        let before = previous_significant(tokens, probe);
        if before >= 0 && tokens[before].end_line == tokens[probe].line {
            break;
        }
        start = probe;
        probe -= 1;
    }
    return start;
}

fn function_declaration_breaks_all(tokens: lexer::Token[:]) -> bool[>..] {
    var breaks: bool[>..] = [];
    for _ in tokens.len {
        breaks.push(false);
    }
    var seen: bool[>..<] = [false];
    for i in tokens.len {
        let token = tokens[i];
        let next = next_significant(tokens, i + 1);
        if token.kind == lexer::IDENT && token.text == "fn" && next < tokens.len
            && (tokens[next].kind == lexer::IDENT || tokens[next].text == "::") {
            if seen[seen.len - 1] {
                breaks[function_declaration_start(tokens, i)] = true;
            }
            seen[seen.len - 1] = true;
        }
        if token.text == "{" {
            seen.push(false);
        } else if token.text == "}" && seen.len > 1 {
            seen.pop();
        }
    }
    return breaks;
}

fn needs_space(tokens: lexer::Token[:], previous_index: i64, current_index: i64, marks: bool[:]) -> bool {
    if previous_index < 0 {
        return false;
    }
    let p = tokens[previous_index];
    let current = tokens[current_index];
    let c = current.text;
    if c == "<" && marks[current_index] && p.text == "for" {
        let before_for = previous_significant(tokens, previous_index);
        if before_for >= 0 && tokens[before_for].text == "const" {
            return true;
        }
    }
    if marks[previous_index] && (p.text == ">" || p.text == ">>") && c == "in" {
        return true;
    }
    if marks[previous_index] || marks[current_index] {
        return false;
    }
    if is_unary(tokens, current_index) {
        if is_unary(tokens, previous_index) {
            return false;
        }
        if c == "&" && p.kind == lexer::IDENT {
            return true;
        }
        return p.kind == lexer::IDENT && (p.text == "return" || p.text == "for"
            || p.text == "in" || p.text == "if" || p.text == "while"
            || p.text == "guard" || p.text == "match" || p.text == "else");
    }
    return ordinary_space(tokens, previous_index, current_index);
}

fn ordinary_space(tokens: lexer::Token[:], previous_index: i64, current_index: i64) -> bool {
    let p = tokens[previous_index];
    let current = tokens[current_index];
    let c = current.text;
    if c == "," || c == ";" || c == ")" || c == "]" || c == "."
        || c == "::" || c == "?" || c == ":" {
        return false;
    }
    if p.text == "(" || p.text == "[" || p.text == "." || p.text == "::" {
        return false;
    }
    if p.text == "]" && c == "var" && previous_index >= 2
        && tokens[previous_index - 2].text == "reusable" {
        return true;
    }
    if c == "{" {
        return true;
    }
    if p.text == "," || p.text == ":" {
        return true;
    }
    if c == "(" {
        return p.kind == lexer::IDENT && (p.text == "return" || p.text == "if"
            || p.text == "while" || p.text == "for" || p.text == "match");
    }
    if c == "[" {
        if p.kind == lexer::IDENT && (p.text == "return" || p.text == "break") {
            return true;
        }
        if is_binary_operator(p.text) {
            return true;
        }
        return false;
    }
    if is_unary(tokens, previous_index) {
        return false;
    }
    if is_binary_operator(p.text) {
        return true;
    }
    if p.text == "!" || p.text == "~" {
        return false;
    }
    if p.kind == lexer::COMMENT {
        return true;
    }
    if p.text == "}" && current.text == "else" {
        return true;
    }
    if is_binary_operator(c) {
        return false;
    }
    if p.kind == lexer::IDENT && (p.text == "return" || p.text == "break"
        || p.text == "if" || p.text == "while" || p.text == "for"
        || p.text == "guard" || p.text == "match" || p.text == "in"
        || p.text == "from" || p.text == "else" || p.text == "fn"
        || p.text == "struct" || p.text == "enum" || p.text == "namespace"
        || p.text == "import" || p.text == "type" || p.text == "let"
        || p.text == "var" || p.text == "const" || p.text == "recursive"
        || p.text == "extern" || p.text == "export" || p.text == "checkfree"
        || p.text == "simd" || p.text == "inline" || p.text == "thread_fn"
        || p.text == "reusable") {
        return true;
    }
    return (p.kind == lexer::IDENT || p.kind == lexer::NUMBER || p.kind == lexer::STRING
        || p.kind == lexer::CHARACTER) && (current.kind == lexer::IDENT
        || current.kind == lexer::NUMBER || current.kind == lexer::STRING
        || current.kind == lexer::CHARACTER);
}
