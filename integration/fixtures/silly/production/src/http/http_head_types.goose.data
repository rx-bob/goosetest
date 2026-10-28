// Typed head outcomes and offset-only incremental state.
namespace silly;
enum HeadResult {
    NeedMore,
    Complete,
    BadRequest,
    Truncated,
    RequestLineLimit,
    HeadLimit,
    HeaderLimit,
    UnsupportedMethod,
    UnsupportedBody,
    UnsupportedVersion,
    UnsupportedTransferCoding,
}
enum BodyFraming {
    None,
    Fixed,
    Chunked,
}
struct HeadFraming {
    result: HeadResult = HeadResult.Complete,
    kind: BodyFraming = BodyFraming.None,
    content_length: i64 = 0,
}
enum TargetForm {
    Origin,
    Absolute,
    Authority,
    Asterisk,
}
struct HeadScan {
    checked_bytes: i64 = 0,
    head_bytes: i64 = 0,
    line_start: i64 = 0,
    request_line_end: i64 = -1,
    header_section_start: i64 = 0,
    field_count: i64 = 0,
    pending_cr: bool = false,
    result: HeadResult = HeadResult.NeedMore,
}
struct ParsedHead {
    result: HeadResult = HeadResult.BadRequest,
    method: const u8[:] = "",
    target: const u8[:] = "",
    target_form: TargetForm = TargetForm.Origin,
    authority: const u8[:] = "",
    http_minor: i32 = 1,
    head_bytes: i64 = 0,
    framing: BodyFraming = BodyFraming.None,
    content_length: i64 = 0,
}
fn head_status(result: HeadResult) -> i32 {
    match result {
        Complete => {
            return 0;
        },
        NeedMore => {
            return 0;
        },
        RequestLineLimit => {
            return 414;
        },
        HeadLimit => {
            return 431;
        },
        HeaderLimit => {
            return 431;
        },
        UnsupportedVersion => {
            return 505;
        },
        UnsupportedTransferCoding => {
            return 501;
        },
        UnsupportedBody => {
            return 501;
        },
        UnsupportedMethod => {
            return 501;
        },
        _ => {
            return 400;
        },
    }
}

fn finish_head(scan: HeadScan&) -> HeadResult {
    if scan.result == HeadResult.NeedMore {
        scan.result = HeadResult.Truncated;
    }
    return scan.result;
}
