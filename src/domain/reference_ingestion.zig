//! Execution-local reference evidence. No canonical snapshot, claim or citation
//! authority is created by inventory, capture or decoding.
const std = @import("std");
const reference = @import("reference_selector.zig");
const identity = @import("filesystem_identity.zig");

pub const Limits = struct {
    entries: usize = 1024,
    depth: usize = 16,
    source_file_bytes: usize = 1024 * 1024,
    source_corpus_bytes: usize = 8 * 1024 * 1024,
    decoded_corpus_bytes: usize = 8 * 1024 * 1024,
    blocks_per_file: usize = 1024,
    block_bytes: usize = 16 * 1024,
    duration_ms: i64 = 5000,
};
pub const limits: Limits = .{};
pub const Error = std.mem.Allocator.Error || error{ InvalidReferenceInventory, InvalidReferenceAccounting };
pub const SourceId = struct { ordinal: u32 };
pub const BlockId = struct { source: SourceId, ordinal: u32 };
pub const RelativePath = struct { bytes: []const u8 };
pub const FileObservation = identity.FileObservation;
pub const Observation = @import("source_inventory.zig").Observation;
pub const Descriptor = @import("source_inventory.zig").Descriptor;
pub const RawInventory = struct { directory: reference.Directory, entries: []const Descriptor };
pub const Entry = struct {
    id: SourceId,
    path: RelativePath,
    /// Filesystem spelling retained only to re-open the observed entry safely.
    raw_path: []const u8,
    observation: Observation,
};
pub const Inventory = struct { directory: reference.Directory, entries: []const Entry };
pub const Failure = enum {
    symlink,
    special,
    unreadable,
    source_size,
    source_budget,
    source_capture,
    unsupported_media,
    malformed_text,
    decoded_budget,
    decoder_failure,
};
pub const Debit = struct {
    reserved: usize,
    outcome: union(enum) { committed: usize, released: void },
};
pub const Capture = union(enum) {
    directory: void,
    blocked: Failure,
    bytes: []const u8,
};
pub const CapturedEntry = struct { entry: Entry, source: Capture, debit: ?Debit };
pub const CapturedCorpus = struct {
    inventory: Inventory,
    entries: []const CapturedEntry,
    source_bytes: usize,
    budget_revision: u32,
};
/// Offsets are zero-based UTF-8 bytes; line/column are one-based Unicode scalar
/// coordinates. End positions are exclusive. CRLF is one line ending.
pub const Position = @import("source_coordinates.zig").Position;
pub const Span = @import("source_coordinates.zig").Span;
pub const BlockProposal = struct { span: Span };
pub const ReaderId = enum { markdown_source_v1 };
pub const Decoded = struct {
    reader: ReaderId,
    media: enum { markdown },
    blocks: []const BlockProposal,
};
pub const DecodeResult = union(enum) {
    directory: void,
    blocked: Failure,
    decoded: Decoded,
    empty: Decoded,
};
pub const DecodedEntry = struct { captured: CapturedEntry, result: DecodeResult, debit: ?Debit };
pub const DecodedCorpus = struct {
    captured: CapturedCorpus,
    entries: []const DecodedEntry,
    decoded_bytes: usize,
    budget_revision: u32,
};
pub const Block = struct { id: BlockId, span: Span };
pub const Document = struct {
    source: SourceId,
    path: RelativePath,
    reader: ReaderId,
    media: @FieldType(Decoded, "media"),
    bytes: []const u8,
    blocks: []const Block,
};
pub const Inputs = struct {
    inventory: Inventory,
    documents: []const Document,
    source_bytes: usize,
    decoded_bytes: usize,
};

pub fn advance(bytes: []const u8, position: Position) error{InvalidReferenceAccounting}!Position {
    return @import("source_coordinates.zig").advance(bytes, position) catch error.InvalidReferenceAccounting;
}
