// Preflight identity bytes before copying metadata or reserving a case record.
namespace goosetest;

import src.runtime.results;

fn reserve_case(results: Results&, identity: CaseIdentity, reason: u8[:] = "") -> i64 {
    assert( !results.active);
    if results.incomplete {
        return - 1;
    }
    if results.cases.len >= results.limits.cases {
        stop_run(results, TerminalError.CaseLimit);
        return - 1;
    }
    if !metadata_fits(results, identity, reason) {
        stop_run(results, TerminalError.MetadataLimit);
        return - 1;
    }
    let id = CaseId {
        test_path: store_metadata(results, identity.test_path),
        namespace_name: store_metadata(results, identity.namespace_name),
        function_name: store_metadata(results, identity.function_name),
        display_name: store_metadata(results, identity.display_name),
        declaration_line: identity.declaration_line,
    };
    let index = results.cases.len;
    results.cases.push(CaseResult {
            identity: id,
            first_failure: results.failures.len,
            skip_reason: store_metadata(results, reason),
            ..
        });
    return index;
}

fn metadata_fits(results: Results&, identity: CaseIdentity, reason: u8[:]) -> bool {
    let texts: const u8[:][5] = [
        identity.test_path, identity.namespace_name, identity.function_name, identity.display_name, reason,
    ];
    var remaining = results.limits.metadata_bytes - results.metadata.len;
    for text in texts {
        if text.len > remaining {
            return false;
        }
        remaining -= text.len;
    }
    return true;
}

fn store_metadata(results: Results&, text: u8[:]) -> Span {
    let span = Span {
        offset: results.metadata.len,
        length: text.len
    };
    results.metadata.append(text);
    return span;
}
