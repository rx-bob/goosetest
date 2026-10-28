// Supplement goosefmt with the normative 70-line function bound using real lexical tokens.
namespace style_check;

import os;
import std;

import goosetest.src.discovery.lexer;
import goosetest.src.discovery.model;
import goosetest.src.platform.filesystem;
import goosetest.src.platform.process;

recursive fn directory(path: u8[:], recurse: bool, depth: i64, checked: i64&) -> bool {
    if depth > 64 {
        write_stderr("Style traversal exceeded 64 directory levels.\n");
        return false;
    }
    let handle = open_handle(path);
    let fd = if handle > 0 {
        filesystem::directory_fd(handle)
    } else {
        -1
    };
    var valid = handle > 0;
    var child: u8[..4096] = [];
    var visited: i64 = 0;
    while valid && visited < 65536 {
        child.clear();
        let kind = next_path(fd, handle, path, child);
        if kind <= 0 {
            valid = kind == 0;
            break;
        }
        visited += 1;
        if kind == filesystem::DIRECTORY && recurse {
            if !directory(child, true, depth + 1, checked) {
                valid = false;
            }
        } else if kind == filesystem::FILE {
            checked += 1;
            if !source(child) {
                valid = false;
            }
        }
    }
    if visited == 65536 {
        valid = false;
    }
    if handle > 0 && filesystem::close_directory(handle) != 0 {
        valid = false;
    }
    return valid;
}

fn open_handle(path: u8[:]) -> i64 {
    var split: i64 = -1;
    for byte,
    index in path {
        if byte == '/' {
            split = index;
        }
    }
    let parent = if split >= 0 {
        path[..split]
    } else {
        "."
    };
    let name = path[split + 1..];
    let fd = filesystem::open_project(parent);
    if fd < 0 {
        return fd as i64;
    }
    let handle = filesystem::open_directory(fd, name);
    if filesystem::close_project(fd) != 0 {
        if handle > 0 {
            filesystem::close_directory(handle);
        }
        return -1;
    }
    return handle;
}

fn root_sources(checked: i64&) -> bool {
    var names: u8[>..] = [];
    if !list_dir(".", names) || names.len > 1048576 {
        return false;
    }
    var start: i64 = 0;
    var valid = true;
    for byte,
    index in names {
        if byte != '\n' {
            continue;
        }
        let name = names[start..index];
        start = index + 1;
        if name.len > 6 && name[name.len - 6..] == ".goose" && file_exists(name) {
            checked += 1;
            if !source(name) {
                valid = false;
            }
        }
    }
    return valid && start == names.len;
}

fn next_path(fd: i32, handle: i64, path: u8[:], child: u8[..4096]&) -> i32 {
    var name: u8[>..] = [];
    let next = filesystem::next(handle, name);
    if next <= 0 {
        return next as i32;
    }
    if path.len + 1 + name.len > 4096 {
        return -1;
    }
    child.append(path);
    child.push('/');
    child.append(name);
    let kind = filesystem::kind(fd, name);
    if kind == filesystem::FILE && (name.len <= 6 || name[name.len - 6..] != ".goose") {
        return filesystem::OTHER;
    }
    return kind;
}

fn source(path: u8[:]) -> bool {
    let result = process::run(["goosefmt", "check", "--config", ".goosefmt.toml", path], ".");
    if result.outcome != process::Outcome.Exited || result.exit_code != 0 || result.cleanup_error != 0 {
        return false;
    }
    var bytes: u8[>..] = [];
    if !read_file(path, bytes) {
        return false;
    }
    var tokens: discovery::Token[>..] = [];
    let error = discovery::lex(bytes, tokens);
    if error.issue != discovery::SyntaxIssue.None {
        write_stderr(str(path, ": cannot lex shipping source for function limits.\n"));
        return false;
    }
    return functions(path, bytes, tokens);
}

fn functions(path: u8[:], bytes: u8[:], tokens: discovery::Token[:]) -> bool {
    var index: i64 = 0;
    while index < tokens.len {
        let token = tokens[index];
        if token.kind != discovery::TokenKind.Identifier || discovery::token_text(bytes, token) != "fn" {
            index += 1;
            continue;
        }
        let start = token.location.line;
        index += 1;
        while index < tokens.len {
            let current = tokens[index];
            let text = discovery::token_text(bytes, current);
            if text == ";" {
                index += 1;
                break;
            }
            if text == "{" && current.mate >= 0 {
                let length = tokens[current.mate].end_line - start + 1;
                if length > 70 {
                    write_stderr(str(path, ":", start, ": function exceeds 70 lines (", length, ").\n"));
                    return false;
                }
                index = current.mate + 1;
                break;
            }
            if current.mate > index {
                index = current.mate + 1;
            } else {
                index += 1;
            }
        }
    }
    return true;
}
