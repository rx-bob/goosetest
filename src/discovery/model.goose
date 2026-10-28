// Owned inventory arenas are borrowed by a small context; incomplete scans are never successful.
namespace discovery;

struct Limits {
    max_entries: i64 = 65536,
    max_depth: i64 = 64,
    max_path_bytes: i64 = 4096,
    max_path_storage_bytes: i64 = 8388608,
    max_file_bytes: i64 = 1048576,
    max_source_bytes: i64 = 67108864,
}
struct Span {
    offset: i64 = 0,
    length: i64 = 0
}
enum RootKind {
    Source,
    Unit,
    Integration
}
struct SourceFile {
    path: Span,
    source: Span,
    kind: RootKind,
    root: i64 = -1,
    pair: i64 = -1,
    target: i64 = -1,
}
struct RootRecord {
    path: Span,
    kind: RootKind,
    target: i64 = -1,
    pair: i64 = -1,
}
struct ExclusionRule {
    path: Span,
    target: i64,
    directory: bool,
}
enum Error {
    None,
    InvalidLimits,
    OpenProject,
    MissingRoot,
    RootNotDirectory,
    InspectEntry,
    ListDirectory,
    OpenDirectory,
    ReadSource,
    CloseDirectory,
    CloseProject,
    Symlink,
    UnsupportedKind,
    InvalidImport,
    EntryLimit,
    DepthLimit,
    PathLimit,
    PathStorageLimit,
    FileSizeLimit,
    SourceSizeLimit,
}
struct Inventory {
    files: SourceFile[>..]&,
    roots: RootRecord[>..]&,
    exclusions: ExclusionRule[>..]&,
    paths: u8[>..]&,
    sources: u8[>..]&,
    error_path: u8[>..]&,
    limits: Limits,
    visited_entries: i64 = 0,
    error: Error = Error.None,
    system_error: i64 = 0,
    limit: i64 = -1,
    started: bool = false,
    complete: bool = false,
    configured: bool = false,
    mirror_disabled: bool = false,
}

struct InventoryBuffers {
    files: SourceFile[>..]&,
    roots: RootRecord[>..]&,
    exclusions: ExclusionRule[>..]&,
    paths: u8[>..]&,
    sources: u8[>..]&,
    error_path: u8[>..]&,
}

// Syntax limits are independent of filesystem budgets and also apply to direct source inputs.
struct SyntaxLimits {
    max_file_bytes: i64 = 1048576,
    max_total_bytes: i64 = 67108864,
    max_tokens: i64 = 262144,
    max_nesting: i64 = 128,
    max_suites: i64 = 4096,
    max_cases: i64 = 65536,
    max_text_bytes: i64 = 8388608,
}
struct SourceLocation {
    line: i64 = 1,
    column: i64 = 1
}
struct ScanError {
    issue: SyntaxIssue = SyntaxIssue.None,
    location: SourceLocation = SourceLocation {
    }
}

enum SyntaxIssue {
    None,
    FileBytes,
    Tokens,
    Nesting,
    UnclosedDelimiter,
    UnmatchedDelimiter,
    MismatchedDelimiter,
    CommentNesting,
    UnterminatedComment,
    UnterminatedRaw,
    CharacterWidth,
    QuotedNewline,
    UnterminatedQuote,
    UnterminatedEscape,
    HexEscape,
    UnknownEscape,
    AnnotationLine,
    MalformedAnnotation,
    UnknownAnnotation,
    AnnotationArgument,
    DuplicateAnnotation,
    EmptyDisabled,
    AnnotationModifiers,
    OrphanAnnotation,
    UnexpectedToken,
    Identifier,
    ParameterType,
    ParameterCount,
    OpeningDelimiter,
    FunctionBody,
    DanglingModifier,
    NamespaceOrder,
    DuplicateNamespace,
    DuplicateFixture,
    FixtureShape,
    ParameterList,
    FunctionModifiers,
    TestSignature,
    HookSignature,
    DuplicateHook,
    MissingNamespace,
    MissingFixture,
    InvalidSyntaxLimits,
    TextBytes,
    IncompleteInventory,
    DuplicateCase,
    SuiteCollision,
    Suites,
    TotalBytes,
    Cases,
    BadTestFilename,
    EmptySuite,
    NoCases,
}

fn new_inventory(
    buffers: InventoryBuffers&, limits: Limits = Limits {
    }
) -> Inventory {
    assert(buffers.files.len == 0);
    assert(buffers.roots.len == 0);
    assert(buffers.exclusions.len == 0);
    assert(buffers.paths.len == 0);
    assert(buffers.sources.len == 0);
    assert(buffers.error_path.len == 0);
    var inventory = Inventory {
        files: buffers.files,
        roots: buffers.roots,
        exclusions: buffers.exclusions,
        paths: buffers.paths,
        sources: buffers.sources,
        error_path: buffers.error_path,
        limits: limits,
        ..
    };
    let values: i64[6] = [limits.max_entries, limits.max_depth, limits.max_path_bytes,
        limits.max_path_storage_bytes, limits.max_file_bytes, limits.max_source_bytes];
    for value in values {
        if value < 0 {
            fail(inventory, Error.InvalidLimits, "");
        }
    }
    return inventory;
}

fn fail(inventory: Inventory&, error: Error, path: u8[:], system_error: i64 = 0, limit: i64 = -1) {
    if inventory.error != Error.None {
        return;
    }
    inventory.error = error;
    inventory.system_error = system_error;
    inventory.limit = limit;
    inventory.error_path.append(path);
}

fn path_text(inventory: Inventory&, span: Span) -> const u8[:] {
    return inventory.paths[span.offset..span.offset + span.length];
}

fn source_text(inventory: Inventory&, file: SourceFile) -> const u8[:] {
    return inventory.sources[file.source.offset..file.source.offset + file.source.length];
}

fn status(inventory: Inventory&) -> i32 {
    if inventory.complete && inventory.error == Error.None {
        return 0;
    }
    return 2;
}
