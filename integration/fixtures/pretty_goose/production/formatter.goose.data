// Goose source formatter.
namespace formatter;

import formatter_imports;
import formatter_rules;
import lexer;

struct FormatConfig {
    indent_width: i64,
    final_newline: bool,
}

struct Writer {
    indent: i64,
    indent_width: i64,
    previous_index: i64,
    source_newlines: i64,
    square_depth: i64,
    delimiter_count: i64,
    delimiters: u8[256],
    block_contexts: i32[256],
    line_start: bool,
    pending_space: bool,
    extra_indent: bool,
    output: u8[>..],
}

fn writer(config: FormatConfig) -> Writer {
    return Writer {
        indent: 0,
        indent_width: config.indent_width,
        previous_index: -1,
        source_newlines: 0,
        square_depth: 0,
        delimiter_count: 0,
        delimiters: [0; 256],
        block_contexts: [0; 256],
        line_start: true,
        pending_space: false,
        extra_indent: false,
        output: [],
    };
}

fn spaces(w: Writer&, count: i64) {
    for _ in count {
        w.output.push(' ');
    }
}

fn ensure_indent(w: Writer&) {
    if !w.line_start {
        return;
    }
    var continuation = false;
    for i in w.delimiter_count {
        if w.delimiters[i] == '(' || w.delimiters[i] == '[' {
            continuation = true;
        }
    }
    let levels = w.indent + (if continuation || w.extra_indent {
            1
        } else {
            0
        });
    spaces(w, levels * w.indent_width);
    w.line_start = false;
    w.extra_indent = false;
}

fn write_raw(w: Writer&, text: const u8[:]) {
    if text.len == 0 {
        return;
    }
    if w.pending_space && !w.line_start && text[0] != '\n' && text[0] != '\r' {
        w.output.push(' ');
    }
    w.pending_space = false;
    if text[0] != '\n' && text[0] != '\r' {
        ensure_indent(w);
    }
    w.output.append(text);
    let last = text[text.len - 1];
    w.line_start = last == '\n' || last == '\r';
}

fn write_char(w: Writer&, byte: u8) {
    var one: u8[1] = [byte];
    write_raw(w, one);
}

fn space(w: Writer&) {
    if !w.line_start {
        w.pending_space = true;
    }
}

fn newline(w: Writer&) {
    w.pending_space = false;
    w.extra_indent = false;
    if w.output.len > 0 && w.output[w.output.len - 1] != '\n' {
        w.output.push('\n');
    }
    w.line_start = true;
}

fn blank_line(w: Writer&) {
    if w.output.len == 0 {
        return;
    }
    newline(w);
    if w.output[w.output.len - 1] == '\n'
        && (w.output.len < 2 || w.output[w.output.len - 2] != '\n') {
        w.output.push('\n');
    }
    w.line_start = true;
}

fn push_delimiter(w: Writer&, delimiter: u8, context: i32) {
    if w.delimiter_count < w.delimiters.len {
        w.delimiters[w.delimiter_count] = delimiter;
        w.block_contexts[w.delimiter_count] = context;
        w.delimiter_count += 1;
    }
}

fn pop_delimiter(w: Writer&) {
    if w.delimiter_count > 0 {
        w.delimiter_count -= 1;
    }
}

fn is_binary_operator(text: const u8[:]) -> bool {
    return text == "=" || text == ".=" || text == "+" || text == "-" || text == "&"
        || text == "*" || text == "/" || text == "%" || text == "=="
        || text == "!=" || text == "<" || text == ">" || text == "<="
        || text == ">=" || text == "&&" || text == "||" || text == "|"
        || text == "^" || text == "<<" || text == ">>" || text == "+="
        || text == "-=" || text == "*=" || text == "/=" || text == "%="
        || text == "&=" || text == "|=" || text == "^=" || text == "<<="
        || text == ">>=" || text == "->" || text == "=>";
}

fn is_unary(tokens: lexer::Token[:], index: i64) -> bool {
    return is_unary_context(tokens, index);
}

fn function_declaration_breaks(tokens: lexer::Token[:]) -> bool[>..] {
    return function_declaration_breaks_all(tokens);
}

fn write_source_newline(w: Writer&, tokens: lexer::Token[:], i: i64) {
    let token = tokens[i];
    if token.kind == lexer::NEWLINE {
        w.source_newlines += 1;
        if !w.line_start {
            let next = next_significant(tokens, i + 1);
            if next >= tokens.len || tokens[next].text != "else" {
                newline(w);
            }
        } else if w.source_newlines >= 2 {
            blank_line(w);
        }
        let next = next_significant(tokens, i + 1);
        if next < tokens.len && is_binary_operator(tokens[next].text)
            && !is_unary(tokens, next) && !is_array_bound(tokens, next, w.square_depth) {
            w.extra_indent = true;
        }
    }
}

fn write_brace(w: Writer&, tokens: lexer::Token[:], i: i64) -> bool {
    let token = tokens[i];
    if token.text == "{" && token.kind == lexer::PUNCTUATION {
        if !w.line_start {
            space(w);
        }
        write_char(w, '{');
        w.indent += 1;
        push_delimiter(w, '{', block_context(tokens, i));
        newline(w);
        return true;
    }

    if token.text == "}" && token.kind == lexer::PUNCTUATION {
        if !w.line_start {
            newline(w);
        }
        if w.indent > 0 {
            w.indent -= 1;
        }
        if w.delimiter_count > 0 && w.delimiters[w.delimiter_count - 1] == '{' {
            pop_delimiter(w);
        }
        write_char(w, '}');
        let next = next_significant(tokens, i + 1);
        if !has_trailing_comment(tokens, i) && (next >= tokens.len
            || (tokens[next].text != "else" && tokens[next].text != ";"
            && tokens[next].text != "," && tokens[next].text != ")"
            && tokens[next].text != "]" && tokens[next].text != "."
            && tokens[next].text != "::" && !is_binary_operator(tokens[next].text))) {
            newline(w);
        }
        return true;
    }
    return false;
}

fn write_delimiter(w: Writer&, tokens: lexer::Token[:], i: i64, marks: bool[:]) -> bool {
    let token = tokens[i];
    if token.text == "(" || token.text == "[" {
        if needs_space(tokens, w.previous_index, i, marks) {
            space(w);
        }
        write_raw(w, token.text);
        if token.text == "[" {
            w.square_depth += 1;
            push_delimiter(w, '[', 0);
        } else {
            push_delimiter(w, '(', 0);
        }
        return true;
    }

    if token.text == ")" || token.text == "]" {
        pop_delimiter(w);
        write_raw(w, token.text);
        if token.text == "]" && w.square_depth > 0 {
            w.square_depth -= 1;
        }
        return true;
    }
    return false;
}

fn write_separator(w: Writer&, tokens: lexer::Token[:], i: i64) -> bool {
    let token = tokens[i];
    if token.text == ";" {
        write_char(w, ';');
        if w.delimiter_count > 0 && w.delimiters[w.delimiter_count - 1] == '[' {
            space(w);
        } else if !has_trailing_comment(tokens, i) {
            newline(w);
        }
        return true;
    }

    if token.text == "," {
        write_char(w, ',');
        let top = w.delimiter_count - 1;
        let in_layout_block = top >= 0 && w.delimiters[top] == '{'
            && w.block_contexts[top] == BLOCK_LAYOUT;
        if in_layout_block && !has_trailing_comment(tokens, i) {
            newline(w);
        } else {
            space(w);
        }
        return true;
    }

    if token.text == ":" {
        write_char(w, ':');
        if w.delimiter_count == 0 || w.delimiters[w.delimiter_count - 1] != '[' {
            space(w);
        }
        return true;
    }

    if token.text == "." || token.text == "::" {
        write_raw(w, token.text);
        return true;
    }
    return false;
}

fn write_token(w: Writer&, tokens: lexer::Token[:], i: i64, marks: bool[:]) {
    let token = tokens[i];
    if token.kind == lexer::COMMENT {
        if !w.line_start {
            space(w);
        }
        write_raw(w, token.text);
        if token.text.starts_with("//") {
            newline(w);
        }
        return;
    }
    if write_brace(w, tokens, i) || write_delimiter(w, tokens, i, marks)
        || write_separator(w, tokens, i) {
        return;
    }
    if marks[i] {
        if needs_space(tokens, w.previous_index, i, marks) {
            space(w);
        }
        write_raw(w, token.text);
        return;
    }

    if token.kind == lexer::OPERATOR {
        if token.text == "?" || token.text == "++" || token.text == "--" {
            write_raw(w, token.text);
        } else if token.text == "&" && is_type_reference(tokens, i) {
            write_raw(w, token.text);
        } else if is_array_bound(tokens, i, w.square_depth) {
            write_raw(w, token.text);
        } else if token.text == "!" || token.text == "~" || is_unary(tokens, i) {
            if needs_space(tokens, w.previous_index, i, marks) {
                space(w);
            }
            write_raw(w, token.text);
        } else {
            if !w.line_start {
                space(w);
            }
            write_raw(w, token.text);
            space(w);
        }
        return;
    }
    if needs_space(tokens, w.previous_index, i, marks) {
        space(w);
    }
    write_raw(w, token.text);
}

fn format_source(source: const u8[:], config: FormatConfig) -> u8[>..] {
    let import_source = format_imports(source);
    let tokens = lexer::lex(import_source);
    let marks = generic_angles(tokens);
    let function_breaks = function_declaration_breaks(tokens);
    var w = writer(config);
    for i in tokens.len {
        if function_breaks[i] {
            blank_line(w);
        }
        if tokens[i].kind == lexer::NEWLINE {
            write_source_newline(w, tokens, i);
            continue;
        }
        w.source_newlines = 0;
        write_token(w, tokens, i, marks);
        w.previous_index = i;
    }
    if config.final_newline && w.output.len > 0 && w.output[w.output.len - 1] != '\n' {
        w.output.push('\n');
    }
    return copy(w.output);
}
