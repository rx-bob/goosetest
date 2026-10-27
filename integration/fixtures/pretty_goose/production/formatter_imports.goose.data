// Sort import declarations without moving surrounding code or losing comments.
namespace formatter;

import formatter_import_rules;
import lexer;

fn without_imports(source: const u8[:], start: i64, end: i64, entries: ImportDecl[:]) -> u8[>..] {
    var output: u8[>..] = [];
    var cursor = start;
    for entry in entries {
        if entry.end <= cursor || entry.start >= end {
            continue;
        }
        if entry.start > cursor {
            output.append(source[cursor..entry.start]);
        }
        cursor = if entry.end < end {
            entry.end
        } else {
            end
        };
    }
    output.append(source[cursor..end]);
    return output;
}

fn sort_imports(tokens: lexer::Token[:], entries: ImportDecl[:]) {
    var i: i64 = 1;
    while i < entries.len {
        let entry = entries[i];
        var at = i;
        while at > 0 && import_before(tokens, entry, entries[at - 1]) {
            entries[at] = entries[at - 1];
            at -= 1;
        }
        entries[at] = entry;
        i += 1;
    }
}

fn write_import(output: u8[>..]&, source: const u8[:], tokens: lexer::Token[:], entry: ImportDecl) {
    let leading = trim(source[entry.start..tokens[entry.first].start]);
    if leading.len > 0 {
        output.append(leading);
        output.push('\n');
    }
    for i in entry.first + 1..entry.last {
        if tokens[i].kind == lexer::COMMENT {
            output.append(tokens[i].text);
            output.push('\n');
        }
    }
    output.append("import ");
    for i in entry.name_start..entry.name_end {
        if tokens[i].kind != lexer::COMMENT && tokens[i].kind != lexer::NEWLINE {
            output.append(tokens[i].text);
        }
    }
    if entry.source_index >= 0 {
        output.append(" from ");
        output.append(tokens[entry.source_index].text);
    }
    output.push(';');
    output.append(source[tokens[entry.last].end..entry.end]);
}

fn format_imports(source: const u8[:]) -> u8[>..] {
    let tokens = lexer::lex(source);
    var entries, namespace_end, first_declaration = scan_imports(tokens);
    if entries.len == 0 {
        var unchanged: u8[>..] = [];
        unchanged.append(source);
        return unchanged;
    }
    let insertion = import_insertion(tokens, namespace_end);
    attach_import_comments(tokens, entries, insertion);
    let prefix = without_imports(source, 0, insertion, entries);
    let suffix = without_imports(source, insertion, source.len, entries);
    sort_imports(tokens, entries);
    var output: u8[>..] = [];
    output.append(trim(prefix));
    if output.len > 0 {
        output.append("\n\n");
    }
    for i in entries.len {
        if i > 0 {
            output.push('\n');
            if entries[i - 1].group != entries[i].group {
                output.push('\n');
            }
        }
        write_import(output, source, tokens, entries[i]);
    }
    if trim(suffix).len > 0 {
        output.append("\n\n");
        output.append(trim(suffix));
    }
    if source.len > 0 && source[source.len - 1] == '\n' {
        output.push('\n');
    }
    return output;
}
