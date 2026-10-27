// Token spans and comparisons for import declarations.
namespace formatter;

import lexer;

struct ImportDecl {
    first: i64,
    last: i64,
    name_start: i64,
    name_end: i64,
    source_index: i64,
    group: i64,
    start: i64,
    end: i64,
}

struct ImportProblem {
    line: i64,
    column: i64,
}

fn standard_import(name: const u8[:]) -> bool {
    return name == "base64" || name == "binary" || name == "csv" || name == "dictionary"
        || name == "exception" || name == "json" || name == "math" || name == "os"
        || name == "regex" || name == "std" || name == "vec";
}

fn import_text_compare(left: const u8[:], right: const u8[:]) -> i64 {
    var i: i64 = 0;
    while i < left.len && i < right.len {
        if left[i] != right[i] {
            return if left[i] < right[i] {
                -1
            } else {
                1
            };
        }
        i += 1;
    }
    return left.len - right.len;
}

fn read_import(tokens: lexer::Token[:], index: i64) -> ImportDecl {
    let name = next_significant(tokens, index + 1);
    var entry = ImportDecl {
        first: index,
        last: -1,
        name_start: name,
        name_end: name,
        source_index: -1,
        group: 2,
        start: tokens[index].start,
        end: tokens[index].end,
    };
    var at = name;
    var expect_name = true;
    if at < tokens.len && tokens[at].text == "." {
        at = next_significant(tokens, at + 1);
    }
    while at < tokens.len {
        if expect_name {
            if tokens[at].kind != lexer::IDENT || tokens[at].text == "from" {
                return entry;
            }
        } else if tokens[at].text != "." {
            break;
        }
        expect_name = !expect_name;
        at = next_significant(tokens, at + 1);
    }
    if expect_name || at >= tokens.len {
        return entry;
    }
    entry.name_end = at;
    if tokens[at].text == "from" {
        entry.group = 0;
        entry.source_index = next_significant(tokens, at + 1);
        at = next_significant(tokens, entry.source_index + 1);
    } else if next_significant(tokens, name + 1) == at && standard_import(tokens[name].text) {
        entry.group = 1;
    }
    if at < tokens.len && tokens[at].text == ";" {
        entry.last = at;
        entry.end = tokens[at].end;
    }
    return entry;
}

fn scan_imports(tokens: lexer::Token[:]) -> ImportDecl[>..], i64, i64 {
    var entries: ImportDecl[>..] = [];
    var namespace_end: i64 = -1;
    var first_declaration: i64 = -1;
    var depth: i64 = 0;
    var i: i64 = 0;
    while i < tokens.len {
        let token = tokens[i];
        if token.kind == lexer::NEWLINE || token.kind == lexer::COMMENT {
            i += 1;
            continue;
        }
        if depth == 0 && token.text == "import" {
            let entry = read_import(tokens, i);
            if entry.last >= 0 {
                entries.push(entry);
                i = entry.last + 1;
                continue;
            }
        }
        if depth == 0 && token.text == "namespace" {
            var end = i + 1;
            while end < tokens.len && tokens[end].text != ";" && tokens[end].text != "{" {
                end += 1;
            }
            if end < tokens.len && tokens[end].text == ";" {
                namespace_end = end;
                i = end + 1;
                continue;
            }
        }
        if depth == 0 && first_declaration < 0 {
            first_declaration = i;
        }
        if token.text == "{" {
            depth += 1;
        } else if token.text == "}" && depth > 0 {
            depth -= 1;
        }
        i += 1;
    }
    return entries, namespace_end, first_declaration;
}

fn import_path_compare(tokens: lexer::Token[:], left: ImportDecl, right: ImportDecl) -> i64 {
    var l = left.name_start;
    var r = right.name_start;
    while l < left.name_end && r < right.name_end {
        let comparison = import_text_compare(tokens[l].text, tokens[r].text);
        if comparison != 0 {
            return comparison;
        }
        l = next_significant(tokens, l + 1);
        r = next_significant(tokens, r + 1);
    }
    if l < left.name_end {
        return 1;
    }
    if r < right.name_end {
        return -1;
    }
    return 0;
}

fn import_before(tokens: lexer::Token[:], left: ImportDecl, right: ImportDecl) -> bool {
    if left.group != right.group {
        return left.group < right.group;
    }
    let comparison = import_path_compare(tokens, left, right);
    if comparison != 0 {
        return comparison < 0;
    }
    if left.source_index >= 0 && right.source_index >= 0 {
        return import_text_compare(tokens[left.source_index].text, tokens[right.source_index].text) < 0;
    }
    return false;
}

fn duplicate_import(tokens: lexer::Token[:], left: ImportDecl, right: ImportDecl) -> bool {
    if left.group != right.group || import_path_compare(tokens, left, right) != 0 {
        return false;
    }
    if left.source_index >= 0 && right.source_index >= 0 {
        return tokens[left.source_index].text == tokens[right.source_index].text;
    }
    return true;
}

fn import_insertion(tokens: lexer::Token[:], namespace_end: i64) -> i64 {
    if namespace_end < 0 {
        let first = next_significant(tokens, 0);
        return if first < tokens.len {
            tokens[first].start
        } else {
            0
        };
    }
    var end = namespace_end;
    while end + 1 < tokens.len && tokens[end + 1].kind == lexer::COMMENT
        && tokens[end + 1].line == tokens[end].end_line {
        end += 1;
    }
    return tokens[end].end;
}

fn attach_import_comments(tokens: lexer::Token[:], entries: ImportDecl[:], insertion: i64) {
    for &entry in entries {
        var end = entry.last;
        while end + 1 < tokens.len && tokens[end + 1].kind == lexer::COMMENT
            && tokens[end + 1].line == tokens[end].end_line {
            end += 1;
            entry.end = tokens[end].end;
        }
        var first = entry.first;
        var probe = first - 1;
        while probe >= 0 {
            if tokens[probe].kind == lexer::NEWLINE {
                probe -= 1;
                continue;
            }
            let token = tokens[probe];
            if token.kind != lexer::COMMENT || token.end_line + 1 != tokens[first].line
                || token.start < insertion {
                break;
            }
            if probe > 0 && tokens[probe - 1].end_line == token.line
                && tokens[probe - 1].kind != lexer::NEWLINE {
                break;
            }
            entry.start = token.start;
            first = probe;
            probe -= 1;
        }
    }
}

fn import_group_gap(tokens: lexer::Token[:], previous: ImportDecl, current: ImportDecl) -> bool {
    var last_line = tokens[previous.last].end_line;
    var blank = false;
    for i in previous.last + 1..current.first + 1 {
        let token = tokens[i];
        if token.kind == lexer::NEWLINE {
            continue;
        }
        if token.line > last_line + 1 {
            blank = true;
        }
        last_line = token.end_line;
    }
    return if previous.group == current.group {
        !blank
    } else {
        blank
    };
}

fn import_problems(tokens: lexer::Token[:]) -> ImportProblem[>..] {
    let entries, namespace_end, first_declaration = scan_imports(tokens);
    var problems: ImportProblem[>..] = [];
    for i in entries.len {
        let entry = entries[i];
        var invalid = namespace_end >= 0 && entry.first < namespace_end;
        invalid = invalid || first_declaration >= 0 && entry.first > first_declaration;
        if i > 0 {
            invalid = invalid || import_before(tokens, entry, entries[i - 1])
                || !import_group_gap(tokens, entries[i - 1], entry);
        }
        for prior in i {
            if duplicate_import(tokens, entries[prior], entry) {
                invalid = true;
            }
        }
        if invalid {
            problems.push(ImportProblem {
                    line: tokens[entry.first].line,
                    column: tokens[entry.first].column,
                });
        }
    }
    return problems;
}
