// Lexical path and target-name checks shared by config decoding.
namespace config;

import src.config.json;
import src.config.model;
import src.discovery.paths;

let MAX_NAME = 48;

fn valid_target_name(value: u8[:]) -> bool {
    if value.len == 0 || value.len > MAX_NAME || value[0] < 'a' || value[0] > 'z'
        || value == "all" || value == "cache" {
        return false;
    }
    for c in value {
        if !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_' {
            return false;
        }
    }
    return true;
}

fn valid_path(value: u8[:], file: bool, directory_exclusion: bool) -> bool {
    if value.len == 0 || value.len > 4096 || value[0] == '/' || value[value.len - 1] == '/' {
        return false;
    }
    if file && (value.len <= 6 || value[value.len - 6..] != ".goose") {
        return false;
    }
    for c in value {
        if c == 0 || c == '\\' {
            return false;
        }
    }
    var start: i64 = 0;
    for index in 0..value.len + 1 {
        if index == value.len || value[index] == '/' {
            let segment = value[start..index];
            if segment.len == 0 || segment == "." || segment == ".." {
                return false;
            }
            if !directory_exclusion {
                let import_name = if file && index == value.len {
                    segment[..segment.len - 6]
                } else if segment.len > 6 && segment[segment.len - 6..] == ".goose" {
                    segment[..segment.len - 6]
                } else {
                    segment
                };
                if !discovery::import_segment(import_name) {
                    return false;
                }
            }
            start = index + 1;
        }
    }
    if !file && !directory_exclusion && value.len == 0 {
        return false;
    }
    return true;
}

fn overlaps(left: u8[:], right: u8[:]) -> bool {
    if equal(left, right) {
        return true;
    }
    if left.len < right.len {
        return right.len > left.len && right[..left.len] == left && right[left.len] == '/';
    }
    return left.len > right.len && left[..right.len] == right && left[right.len] == '/';
}

fn validate_overlaps(configuration: Configuration&) -> bool {
    for i in 0..configuration.roots.len {
        for j in 0..i {
            let left = text_value(configuration, configuration.roots[i].path);
            let right = text_value(configuration, configuration.roots[j].path);
            if overlaps(left, right) {
                configuration.error = "test roots overlap";
                configuration.field = "targets.tests.path";
                return false;
            }
        }
    }
    return true;
}
