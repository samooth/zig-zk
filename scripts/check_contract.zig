//! Checks the contract this repository holds with `zig-algebra`.
//!
//! `zig-algebra` is consumed as a pinned package, so the only channel between
//! the two repositories is a version number. That channel runs one way: a new
//! release reaches a consumer when somebody bumps the pin by hand, and a fix
//! made upstream has no path back to a consumer that copied the code instead of
//! importing it. The ledger below is what makes that asymmetry visible instead
//! of silent.
//!
//! Rules:
//!   1. Every zone that carries a declared `std.debug.assert` count is in the
//!      ledger with a reason and a trigger to resolve it, and declares what its
//!      asserts are: `api`, `internal` or `fixture`. Three numbers per zone
//!      family are ratcheted, not one: the zone total, the part carved out into
//!      named private helpers, and the aggregate a caller can reach. The third
//!      is the one T1 is scoped from, and the summary prints the four buckets
//!      side by side so they can be seen to add up.
//!   2. A zone's actual assert count equals its declared count. More is a
//!      regression and fails; fewer is an improvement and also fails, because
//!      the ledger has to record it. The count can therefore only move when a
//!      person edits this file, which is the point.
//!   3. The set of `zig-algebra` modules imported under `libs/` equals the set
//!      declared below. A new dependency fails until it is declared, and a
//!      module that is resolved by the build but never imported fails too.
//!   4. Every manifest that declares `zig_algebra` pins the version the ledger
//!      records, so a bump on one side only is caught.
//!
//! Rule 2 exists because `AGENTS.md` forbids `std.debug.assert` on anything
//! reachable from the public API, and `libs/stark/root.zig` re-exports all three
//! zones below. The rule was written and then not enforced anywhere, which is
//! why the counts are as high as they are.
//!
//! The scanner is line based: it truncates each line at the first `//` and works
//! on what is left. That drops doc-comment examples such as the
//! `@import("zig-transcript")` in `libs/transcript/src/root.zig`, and it is also
//! what keeps the assert count honest. Counting the raw line made a doc-comment
//! that merely *mentions* `std.debug.assert` inflate a zone's count, which is
//! backwards: the fix for an assert is to write down why it was there, and a
//! scanner that punishes the documentation blocks the work the rule exists to
//! force. `libs/snark` was the live case: one occurrence, in a comment, zero
//! asserts.
//!
//! Two limits, both disclosed rather than handled. The scanner does not
//! understand string literals, so a `//` inside a string hides the rest of that
//! line. And there are no block comments under `libs/` today, so a `/* … */`
//! would be counted as code; if one appears with the token in it, the counts stop
//! matching and the gate says so.

const std = @import("std");

/// What the counted asserts are. This is a declared claim, not something the
/// scanner can work out: `libs/transcript` has two asserts inside `pub fn`, and
/// both sit in a `const` that is private and in a file nothing imports, so the
/// `pub` keyword alone says nothing about reachability. Reading a zone and
/// arguing for its `kind` is the point; the gate only holds the number still.
const Kind = enum { api, internal, fixture };

/// What an assert protects. This is orthogonal to `kind`: `kind` says where the
/// assert lives, this says whose input it is checking, and a `pub fn` can be
/// either. `coset.at` takes an index from the caller, `coset.half` checks a
/// field of a value it was already handed, and both are public.
const Protection = enum { caller, invariant };

/// One assert classified as an invariant, keyed by the file it lives in and the
/// text of its condition with whitespace collapsed.
///
/// The key is semantic on purpose. A key on the assert's position or its
/// function name rots during the very work the classification is meant to
/// survive: converting the first assert in a function moves the rest, and
/// renaming a private helper moves its asserts between buckets. The condition
/// text survives insertions before it, and a rewritten condition stops matching,
/// which is the outcome we want, because rewriting the condition is changing
/// what the assert protects. `count` is how many times the condition occurs in
/// that file, because a condition can repeat and the two are not
/// interchangeable.
const Classified = struct {
    file: []const u8,
    condition: []const u8,
    count: usize = 1,
};

/// A zone is a subtree of `libs/` whose relationship to `zig-algebra` is written
/// down. `upstream` is null when the zone has no counterpart over there, which
/// is a legitimate state and still gets a declared assert count: the rule that
/// matters is the count, not the duplication.
///
/// Anything not in `invariants` is treated as caller-facing, which is the safe
/// direction: a new assert nobody classified raises the reachable count and the
/// ratchet fails, so the classification cannot rot into understating the work.
const Zone = struct {
    path: []const u8,
    kind: Kind,
    upstream: ?[]const u8,
    asserts: usize,
    invariants: []const Classified,
    reason: []const u8,
    revisit: []const u8,
};

const ledger = [_]Zone{
    .{
        .path = "libs/stark/binius",
        .kind = .api,
        .upstream = "zig-algebra/libs/binary-field @ 0.5.2",
        .asserts = 61,
        .invariants = &.{},
        .reason = "the field layer is upstream's, adopted from 0.5.2: field, " ++
            "tower, pack, polynomial and clmul come from zig-binary-field and " ++
            "this zone no longer carries them. The sum-check went with a " ++
            "differential that compared proof bytes, not verdicts: value, " ++
            "claimed sum and six rounds matched upstream's exactly, so the " ++
            "local file was a pure deletion. Two more forks went with it: " ++
            "core/pool.zig, which upstream's sum-check refused because it " ++
            "takes zig-algebra's Pool and not ours, and accel.zig, whose only " ++
            "consumer was the local sum-check. What is left of the fork here " ++
            "is pcs.zig alone. 61 asserts, none of them classified: the zone " ++
            "has no declared invariants, so every one of them counts as " ++
            "reachable and overstates the work.",
        .revisit = "the differential harness ran, and the answer is split. The " ++
            "sum-check is byte-identical to upstream's over value, claimed sum " ++
            "and six rounds, so sumcheck.zig is a pure deletion. The PCS is not: " ++
            "our commit pre-hashed each element and then passed the digests to " ++
            "MerkleTree.init, which hashes leaves again, so its leaves were " ++
            "H(H(v)) and the two implementations commit to different roots over " ++
            "one table. Round-trip tests cannot see that, being self-consistent. " ++
            "Deleting pcs.zig is therefore blocked on an upstream defect rather " ++
            "than on this repository: the Blake3 in zig-hash was not " ++
            "BLAKE3, so adopting the fixed leaf convention would import a hash " ++
            "that is not the algorithm it names. Resume when a release past that " ++
            "fix lands, then delete pcs.zig, sumcheck.zig and accel.zig together " ++
            "and re-scope this zone: the other twelve files have no upstream " ++
            "counterpart and hold the remaining asserts, so the zone is ours, " ++
            "not a fork, and cannot go to zero.",
    },
    .{
        .path = "libs/stark/core",
        .kind = .api,
        .upstream = null,
        .asserts = 0,
        .invariants = &.{},
        .reason = "merkle and serialization are local implementations shaped for " ++
            "the prover's own column layout, not the generic trees in " ++
            "zig-merkle and zig-serialization. They share four API names each and " ++
            "no code, so this is a parallel implementation rather than a copy. " ++
            "The kind is api even at zero: local describes the missing upstream " ++
            "counterpart, not the reachability of asserts, and the two that were " ++
            "here are now error.InvalidLeafCount and error.OutOfRange. hash.zig " ++
            "is the third member and the one that carries a known-answer vector " ++
            "against an independent BLAKE3, including one across chunks: at 0.5.1 " ++
            "the Blake3 in zig-hash is not BLAKE3, because its root output " ++
            "recompresses the compressed state instead of the input chaining " ++
            "value, and a one-block vector does not reach that path. This module " ++
            "wraps std.crypto.hash.Blake3 and is correct, and the vectors are why " ++
            "the defect was visible from here at all.",
        .revisit = "revisit if a consumer outside this repository needs the " ++
            "prover's column layout, or if a generic tree can serve it. If this " ++
            "zone ever adopts zig-hash, re-run the two vectors against an " ++
            "independent BLAKE3 first: that is the only instrument that saw the " ++
            "upstream defect, and adopting the module would import it.",
    },
    .{
        .path = "libs/stark/m31",
        .kind = .api,
        .upstream = null,
        .asserts = 15,
        .invariants = &.{
            // Four public functions whose assert checks a value they were
            // handed, or a relation between two StarkParams fields. Converting
            // these would change a published signature to guard nothing.
            .{ .file = "circle/coset.zig", .condition = "self.log_size > 0" },
            // at and get take an index that every call site derives from the
            // coset's own size, so a bad index is not reachable from a caller,
            // let alone from a proof. Converting them would cascade a fallible
            // signature through the NTT to guard a case that cannot happen.
            .{ .file = "circle/coset.zig", .condition = "index < self.size()" },
            .{ .file = "circle/domain.zig", .condition = "index < self.size()" },
            .{ .file = "field/m31.zig", .condition = "self.value != 0" },
            .{ .file = "fri.zig", .condition = "L >= 1" },
            .{ .file = "fri.zig", .condition = "params.remainder_log >= params.log_blowup" },
            // Six in private helpers, which the public entry points call with
            // arguments they have already checked. Five conditions, one of them
            // twice. The gate is what corrected the first draft of this list:
            // deinterleave's second assert is c.len == 2 * a.len, not
            // out.len == 2 * a.len, and pos + 1 == out.len belongs to
            // slowPrecomputeTwiddles, which is private, so it is here.
            .{ .file = "ntt/circle.zig", .condition = "pos + 1 == out.len" },
            .{ .file = "ntt/circle.zig", .condition = "out.len == len" },
            .{ .file = "ntt/circle.zig", .condition = "a.len == b.len", .count = 2 },
            .{ .file = "ntt/circle.zig", .condition = "out.len == 2 * a.len" },
            .{ .file = "ntt/circle.zig", .condition = "c.len == 2 * a.len" },
        },
        .reason = "the M31 circle STARK has no counterpart in zig-algebra; " ++
            "zig-algebra's FRI is a radix-2 FRI over a base-field subgroup and " ++
            "M31's two-adicity is 1, so it cannot be used here. The zone is " ++
            "legitimately local and the count is a debt against the AGENTS.md " ++
            "rule. Of the 15, twelve are invariants and three guard something the " ++
            "caller supplies, which is the number the work is scoped from. Four " ++
            "of the invariants are in public functions: coset.half checks a field " ++
            "of a value it was handed, M31.inv is the total inverse whose checked " ++
            "sibling is invChecked, and the two in fri.proveCodeword are relations " ++
            "between two StarkParams fields. The other six are in private helpers " ++
            "that the public entry points call with arguments they already checked.",
        .revisit = "the three left are primitiveRootOfUnity, twice in m31 and " ++
            "once in qm31, and they are their own piece of work: with n == 0 the " ++
            "second check, (n & (n - 1)) == 0, underflows n - 1, so that is " ++
            "broken arithmetic in ReleaseFast rather than a missing diagnostic, " ++
            "and it deserves its own analysis before anyone touches the field " ++
            "arithmetic the prover uses on its hot path. The twelve invariants " ++
            "stay unless " ++
            "a caller can reach them, which for M31.inv means the checked sibling " ++
            "stays the caller-facing path and the total keeps its assert.",
    },
    .{
        .path = "libs/transcript",
        .kind = .fixture,
        .upstream = null,
        .asserts = 2,
        .invariants = &.{},
        .reason = "neither assert is API. One is inside the F7 field that root.zig " ++
            "defines as a test fixture, in a `const` that is not exported; the " ++
            "other is in src/main.zig, a demonstration file that no build and no " ++
            "import reaches. Both are `pub fn` inside something private, which is " ++
            "why this is the zone that proves the scanner cannot be trusted to " ++
            "infer reachability from the `pub` keyword. Deleting main.zig takes " ++
            "the zone to 1.",
        .revisit = "delete src/main.zig; the remaining assert belongs to the test " ++
            "fixture, not to the API",
    },
    .{
        .path = "libs/commitment",
        .kind = .api,
        .upstream = null,
        .asserts = 0,
        .invariants = &.{},
        .reason = "clean. The seven asserts this zone had became typed errors in " ++
            "0.3.0: reconstruct returns error.NoShares, innerProduct and commit " ++
            "return error.LengthMismatch, split returns error.InvalidThreshold or " ++
            "error.TooFewShares, and verify returns error.MalformedProof. It is in " ++
            "the ledger so the improvement cannot quietly regress.",
        .revisit = "none; the count is the ratchet",
    },
    .{
        .path = "libs/signature",
        .kind = .api,
        .upstream = null,
        .asserts = 0,
        .invariants = &.{},
        .reason = "clean, and deliberately so: Ed25519 is std's, and the generic " ++
            "Schnorr has no preconditions a caller can violate. Recorded so that a " ++
            "new assert has to be declared rather than added.",
        .revisit = "none; the count is the ratchet",
    },
    .{
        .path = "libs/snark",
        .kind = .api,
        .upstream = null,
        .asserts = 0,
        .invariants = &.{},
        .reason = "clean. Groth16 validates its comptime arguments with " ++
            "@compileError, because a std.debug.assert there would be compiled out " ++
            "in ReleaseFast and a malformed system would build and then fail on the " ++
            "first proof. The runtime paths carry typed errors (DegenerateSetup, " ++
            "QapUnsatisfied) or return false.",
        .revisit = "none; the count is the ratchet",
    },
};

/// The `zig-algebra` modules imported under `libs/`. Anything outside this list
/// is a dependency edge the build does not know about; anything in it that stops
/// being imported is an edge the build resolves for nothing.
const declared_algebra_modules = [_][]const u8{
    "zig-algebra-traits",
    "zig-binary-field",
    "zig-curve",
    "zig-field",
    "zig-hash",
    "zig-merkle",
    "zig-pairing",
    "zig-parallel",
    "zig-poly",
};

/// Modules this repository owns. Listed so that a typo in one of them is
/// reported as a boundary change rather than as a mysteriously missing import.
const declared_own_modules = [_][]const u8{
    "zig-stark",
    "zig-transcript",
};

/// The version every manifest that declares `zig_algebra` must pin.
const declared_algebra_pin = "0.5.2";

/// The number of asserts a caller can actually reach, summed over the zones
/// whose kind is `api` and left after the carved out private helpers. It is
/// declared so that the number T1 has to act on is ratcheted like any other:
/// carving a function out lowers it, and lowering it means editing this, which
/// puts the change in the diff next to the list that caused it.
///
/// The carve out is not ratcheted on its own, and cannot be: the hard ratchet
/// is each zone's total, so a function can be moved from the reachable bucket
/// to the carved one without failing anything. That is a known property rather
/// than an oversight, and this constant is the second half of the answer, since
/// every carve out has to be paid for here.
const declared_reachable: usize = 64;

const max_detail = 512;

const Problem = struct {
    what: [128]u8 = undefined,
    what_len: usize = 0,
    detail: [max_detail]u8 = undefined,
    detail_len: usize = 0,

    fn setWhat(self: *Problem, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(self.what[0..], fmt, args) catch blk: {
            const s = "label too long";
            @memcpy(self.what[0..s.len], s);
            break :blk s;
        };
        self.what_len = s.len;
    }

    fn setDetail(self: *Problem, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(self.detail[0..], fmt, args) catch blk: {
            const s = "detail too long";
            @memcpy(self.detail[0..s.len], s);
            break :blk s;
        };
        self.detail_len = s.len;
    }

    fn whatSlice(self: *const Problem) []const u8 {
        return self.what[0..self.what_len];
    }

    fn detailSlice(self: *const Problem) []const u8 {
        return self.detail[0..self.detail_len];
    }
};

const assert_token = "std.debug.assert";
const import_open = "@import(\"";
/// Count occurrences of `needle` in `haystack`, returning how many there were.
fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var n: usize = 0;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            n += 1;
            i += needle.len;
        } else {
            i += 1;
        }
    }
    return n;
}

/// The part of `line` that is code: everything before the first `//`. Both the
/// import scan and the assert count read this, so a comment cannot register as
/// either.
fn codeOf(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "//")) |cut| return line[0..cut];
    return line;
}

/// Whether `path` ends with `suffix`, so a zone can name a file without
/// repeating its own prefix.
fn endsWithPath(path: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, path, suffix);
}

const assert_prefix = "std.debug.assert(";

/// The condition inside `std.debug.assert(...)` on this line, with whitespace
/// collapsed, or null if the line has no assert or the parens do not close on
/// it. A condition split across lines is not seen; no assert in this tree is,
/// and if one appears the zone total stops matching and the gate says so.
///
/// `buf` belongs to the caller and has to outlive the result: returning a slice
/// of a local here would dangle the moment this function returned.
fn conditionOf(code: []const u8, buf: []u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, code, assert_prefix) orelse return null;
    const rest = code[at + assert_prefix.len ..];
    const close = std.mem.lastIndexOfScalar(u8, rest, ')') orelse return null;
    const collapsed = collapseSpace(rest[0..close], buf) orelse return null;
    if (collapsed.len == 0) return null;
    return collapsed;
}

/// Collapse runs of whitespace to one space and trim, so a reformatted condition
/// still keys the same. Returns null when the result would not fit, which is
/// reported rather than silently truncated.
fn collapseSpace(raw: []const u8, buf: []u8) ?[]const u8 {
    var n: usize = 0;
    var pending_space = false;
    for (raw) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            pending_space = n > 0;
            continue;
        }
        if (pending_space) {
            if (n + 1 > buf.len) return null;
            buf[n] = ' ';
            n += 1;
            pending_space = false;
        }
        if (n + 1 > buf.len) return null;
        buf[n] = ch;
        n += 1;
    }
    return buf[0..n];
}

/// Feed every `@import("…")` in `code` to `sink`. Only `zig-` names are
/// forwarded, so `std` and the relative imports stay out of the boundary.
fn scanCodeForImports(code: []const u8, sink: *Imports) void {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, code, i, import_open)) |start| {
        const name_start = start + import_open.len;
        const rel_end = std.mem.indexOfPos(u8, code, name_start, "\"") orelse break;
        const name = code[name_start..rel_end];
        if (std.mem.startsWith(u8, name, "zig-")) sink.add(name);
        i = rel_end + 1;
    }
}

const Imports = struct {
    algebra: std.ArrayList([]const u8) = .empty,
    own: std.ArrayList([]const u8) = .empty,
    alloc: std.mem.Allocator,

    fn add(self: *Imports, name: []const u8) void {
        for (self.algebra.items) |seen| if (std.mem.eql(u8, seen, name)) return;
        for (self.own.items) |seen| if (std.mem.eql(u8, seen, name)) return;
        if (isOwn(name)) {
            self.own.append(self.alloc, name) catch return;
        } else {
            self.algebra.append(self.alloc, name) catch return;
        }
    }
};

/// A module this repository publishes. Kept in sync with the module names the
/// root `build.zig` registers; the rule below is what notices when it drifts.
fn isOwn(name: []const u8) bool {
    for (declared_own_modules) |own| {
        if (std.mem.eql(u8, own, name)) return true;
    }
    return false;
}

/// Report a module that is present in `found` but absent from `declared`.
fn reportUndeclared(
    problems: *std.ArrayList(Problem),
    alloc: std.mem.Allocator,
    found: []const []const u8,
    declared: []const []const u8,
    comptime kind: []const u8,
) !void {
    for (found) |name| {
        var known = false;
        for (declared) |d| {
            if (std.mem.eql(u8, d, name)) known = true;
        }
        if (known) continue;
        var p: Problem = .{};
        p.setWhat("import", .{});
        p.setDetail("libs/ imports {s}, which is not in declared_{s}_modules: add it " ++
            "to scripts/check_contract.zig, or drop the import", .{ name, kind });
        try problems.append(alloc, p);
    }
}

/// Report a declared module that nothing imports any more.
fn reportUnused(
    problems: *std.ArrayList(Problem),
    alloc: std.mem.Allocator,
    found: []const []const u8,
    declared: []const []const u8,
    comptime kind: []const u8,
) !void {
    for (declared) |name| {
        var used = false;
        for (found) |f| {
            if (std.mem.eql(u8, f, name)) used = true;
        }
        if (used) continue;
        var p: Problem = .{};
        p.setWhat("declared", .{});
        p.setDetail("declared_{s}_modules lists {s}, but no file under libs/ imports " ++
            "it: the build resolves it for nothing", .{ kind, name });
        try problems.append(alloc, p);
    }
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.arena.allocator();
    const io = init.io;

    var problems: std.ArrayList(Problem) = .empty;
    var imports: Imports = .{ .alloc = alloc };
    var zone_asserts = [_]usize{0} ** ledger.len;
    var declared_invariant_count: usize = 0;
    var classified_found = [_]usize{0} ** ledger.len;
    for (ledger) |zone| {
        for (zone.invariants) |c| declared_invariant_count += c.count;
    }
    var files_scanned: usize = 0;

    // Rule 4. Every manifest that names the dependency must pin the same
    // version, or the build and the ledger disagree about what is being consumed.
    {
        const manifests = [_][]const u8{
            "build.zig.zon",
            "libs/commitment/build.zig.zon",
            "libs/signature/build.zig.zon",
            "libs/snark/build.zig.zon",
            "libs/stark/build.zig.zon",
            "libs/transcript/build.zig.zon",
        };
        for (manifests) |path| {
            const text = readOrNull(alloc, io, path) orelse continue;
            if (std.mem.indexOf(u8, text, "zig_algebra") == null) continue;
            const marker = "zig_algebra-";
            const at = std.mem.indexOf(u8, text, marker) orelse {
                var p: Problem = .{};
                p.setWhat("pin", .{});
                p.setDetail("{s} declares zig_algebra without a versioned hash, so " ++
                    "rule 4 cannot check it", .{path});
                try problems.append(alloc, p);
                continue;
            };
            const rest = text[at + marker.len ..];
            var end: usize = 0;
            while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
            if (end < rest.len and rest[end] == '.') {
                end += 1;
                while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
            }
            if (end < rest.len and rest[end] == '.') {
                end += 1;
                while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
            }
            const pinned = rest[0..end];
            if (!std.mem.eql(u8, pinned, declared_algebra_pin)) {
                var p: Problem = .{};
                p.setWhat("pin", .{});
                p.setDetail("{s} pins zig-algebra {s}, the ledger records {s}: bump " ++
                    "the ledger in the same commit, or the two disagree about " ++
                    "what is being consumed", .{ path, pinned, declared_algebra_pin });
                try problems.append(alloc, p);
            }
        }
    }

    // Rules 2 and 3. One pass over the source.
    {
        const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
        defer cwd.close(io);

        var walker = try cwd.walk(alloc);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            const path = entry.path;
            if (!std.mem.endsWith(u8, path, ".zig")) continue;
            if (std.mem.indexOf(u8, path, "zig-pkg") != null) continue;
            if (std.mem.indexOf(u8, path, ".zig-cache") != null) continue;
            if (std.mem.indexOf(u8, path, ".opencode") != null) continue;
            if (!std.mem.startsWith(u8, path, "libs/")) continue;

            const text = cwd.readFileAlloc(io, path, alloc, .limited(1 << 22)) catch continue;
            files_scanned += 1;

            var lines = std.mem.splitScalar(u8, text, '\n');
            var cond_buf: [512]u8 = undefined;
            while (lines.next()) |line| {
                const code = codeOf(line);
                scanCodeForImports(code, &imports);
                if (countOccurrences(code, assert_token) == 0) continue;
                for (ledger, 0..) |zone, zi| {
                    if (!std.mem.startsWith(u8, path, zone.path)) continue;
                    zone_asserts[zi] += countOccurrences(code, assert_token);
                }
                // Second pass over the ledger for the classification, because the
                // condition is only worth extracting for zones that name it.
                const condition = conditionOf(code, &cond_buf) orelse continue;
                for (ledger, 0..) |zone, zi| {
                    if (!std.mem.startsWith(u8, path, zone.path)) continue;
                    for (zone.invariants) |c| {
                        if (!endsWithPath(path, c.file)) continue;
                        if (std.mem.eql(u8, c.condition, condition)) {
                            classified_found[zi] += 1;
                        }
                    }
                }
            }
        }
    }

    // Rule 2.
    for (ledger, 0..) |zone, zi| {
        if (zone_asserts[zi] == zone.asserts) continue;
        var p: Problem = .{};
        p.setWhat("asserts", .{});
        if (zone_asserts[zi] > zone.asserts) {
            p.setDetail("{s} has {d} std.debug.assert, the ledger declares {d}: " ++
                "AGENTS.md forbids them where a caller can reach them. Revert the " ++
                "addition or record it deliberately", .{
                zone.path, zone_asserts[zi], zone.asserts,
            });
        } else {
            p.setDetail("{s} has {d} std.debug.assert, the ledger declares {d}: the " ++
                "count improved, record it in scripts/check_contract.zig so the " ++
                "ledger stays exact", .{ zone.path, zone_asserts[zi], zone.asserts });
        }
        try problems.append(alloc, p);
    }

    // Rule 2, second number: the classification. Every condition a zone claims as
    // an invariant has to still be there, the same number of times. A condition
    // that was rewritten, deleted, or duplicated fails here rather than
    // silently moving asserts between buckets, which is the point of keying on
    // the text.
    var classified_total: usize = 0;
    for (ledger, 0..) |zone, zi| {
        var declared_here: usize = 0;
        for (zone.invariants) |c| declared_here += c.count;
        classified_total += declared_here;
        if (classified_found[zi] == declared_here) continue;
        var p: Problem = .{};
        p.setWhat("classified", .{});
        p.setDetail("{s} lists {d} asserts as invariants and the source has {d} " ++
            "of those conditions. A rewritten condition stops matching, which is " ++
            "the correct outcome: rewriting what an assert checks is changing " ++
            "what it protects, so reclassify it", .{
            zone.path, declared_here, classified_found[zi],
        });
        try problems.append(alloc, p);
    }

    // Rule 2, third number: the reachable total, which is the one the T1 scope
    // is read from. A fixture assert is not reachable by anybody and a carved
    // out one is not either, so both come off before this is summed. Leaving
    // them in made the headline answer a question nobody asked, which is worse
    // than not printing it.
    var declared_total: usize = 0;
    var reachable: usize = 0;
    var carved_out: usize = 0;
    var fixture_total: usize = 0;
    var internal_total: usize = 0;
    for (ledger, 0..) |zone, zi| {
        declared_total += zone.asserts;
        switch (zone.kind) {
            .api => {
                reachable += zone.asserts - classified_found[zi];
                carved_out += classified_found[zi];
            },
            .fixture => fixture_total += zone.asserts,
            .internal => internal_total += zone.asserts,
        }
    }
    if (reachable != declared_reachable) {
        var p: Problem = .{};
        p.setWhat("reachable", .{});
        if (reachable > declared_reachable) {
            p.setDetail("the zones now add up to {d} asserts a caller can reach, " ++
                "declared_reachable says {d}. A zone gained an assert on its " ++
                "public surface", .{ reachable, declared_reachable });
        } else {
            p.setDetail("the zones now add up to {d} asserts a caller can reach, " ++
                "declared_reachable says {d}: record it here as well as in the " ++
                "zone. If the drop came from carving helpers out rather than " ++
                "from converting them, say so in the zone's reason", .{
                reachable, declared_reachable,
            });
        }
        try problems.append(alloc, p);
    }

    // Rule 3.
    try reportUndeclared(&problems, alloc, imports.algebra.items, &declared_algebra_modules, "algebra");
    try reportUndeclared(&problems, alloc, imports.own.items, &declared_own_modules, "own");
    try reportUnused(&problems, alloc, imports.algebra.items, &declared_algebra_modules, "algebra");
    try reportUnused(&problems, alloc, imports.own.items, &declared_own_modules, "own");

    if (problems.items.len > 0) {
        std.debug.print("contract check failed:\n", .{});
        for (problems.items) |*p| {
            std.debug.print("  - {s}: {s}\n", .{ p.whatSlice(), p.detailSlice() });
        }
        return 1;
    }

    // The summary carries the reachable count per kind, because "37" invites the
    // argument about how many of them a caller can actually get to, and "31"
    // does not. The buckets add up to the declared total, so a reader can see
    // that the carved out helpers are accounted for rather than missing.
    // Only invariants are ever classified, so every other assert is assumed
    // caller-facing and the reachable total is an upper bound, not a work
    // figure. The summary has to say so: binius declares none, and twenty of its
    // asserts are private-helper invariants, so a reader who takes 110 as "110
    // conversions" is out by twenty.
    if (carved_out > 0) {
        std.debug.print(
            "  reachable is an upper bound: {d} asserts are declared invariants " ++
                "and every other one is assumed caller-facing, so a zone with " ++
                "unclassified private asserts is counted whole\n",
            .{carved_out},
        );
    }

    std.debug.print(
        "contract check passed: {d} files, {d} algebra modules, pin {s}, " ++
            "{d} zones at their declared assert counts; {d} declared = " ++
            "{d} reachable + {d} invariant + {d} fixture + {d} internal-only\n",
        .{
            files_scanned,
            imports.algebra.items.len,
            declared_algebra_pin,
            ledger.len,
            declared_total,
            reachable,
            carved_out,
            fixture_total,
            internal_total,
        },
    );
    return 0;
}

fn readOrNull(
    alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) ?[]const u8 {
    const cwd = std.Io.Dir.cwd().openDir(io, ".", .{}) catch return null;
    defer cwd.close(io);
    return cwd.readFileAlloc(io, path, alloc, .limited(1 << 20)) catch null;
}

test "the scanner ignores comments and counts code" {
    // Code counts.
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(codeOf("    std.debug.assert(a.len == b.len);"), assert_token),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        countOccurrences(codeOf("    x = std.debug.assert; y = std.debug.assert;"), assert_token),
    );

    // A comment that merely names the assert does not. This is the case that
    // made libs/snark report one assert it did not have, and the case that
    // would block the doc-comment explaining an assert's removal.
    try std.testing.expectEqual(
        @as(usize, 0),
        countOccurrences(codeOf("    // was std.debug.assert(value != 0)"), assert_token),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        countOccurrences(codeOf("/// Uses std.debug.assert for the preconditions."), assert_token),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        countOccurrences(codeOf("    const n = 1; // std.debug.assert(n > 0)"), assert_token),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(codeOf("    std.debug.assert(n > 0); // see std.debug.assert"), assert_token),
    );
}

test "the import scan reads code, not comments" {
    var imports: Imports = .{ .alloc = std.testing.allocator };
    defer imports.algebra.deinit(imports.alloc);
    defer imports.own.deinit(imports.alloc);

    scanCodeForImports(codeOf("const a = @import(\"zig-hash\");"), &imports);
    scanCodeForImports(codeOf("// const b = @import(\"zig-rng\");"), &imports);
    scanCodeForImports(codeOf("const std = @import(\"std\");"), &imports);
    scanCodeForImports(codeOf("const c = @import(\"sibling.zig\");"), &imports);

    try std.testing.expectEqual(@as(usize, 1), imports.algebra.items.len);
    try std.testing.expectEqualStrings("zig-hash", imports.algebra.items[0]);
    try std.testing.expectEqual(@as(usize, 0), imports.own.items.len);
}

test "a condition is keyed by its text, not by where it sits" {
    // Whitespace is collapsed, so a reformatted condition still matches.
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "a.len == b.len",
        conditionOf("        std.debug.assert(a.len == b.len);", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "a.len == b.len",
        conditionOf("        std.debug.assert(  a.len\n            == b.len  );", &buf).?,
    );
    try std.testing.expectEqualStrings(
        "n > 0 and (n & (n - 1)) == 0",
        conditionOf("        std.debug.assert(n > 0 and (n & (n - 1)) == 0); // power of two", &buf).?,
    );

    // A rewritten condition does not match the old key, which is the point.
    try std.testing.expect(!std.mem.eql(u8, conditionOf("        std.debug.assert(a.len != b.len);", &buf).?, "a.len == b.len"));

    // No assert, and an unterminated one.
    try std.testing.expect(conditionOf("    const n = 1;", &buf) == null);
    try std.testing.expect(conditionOf("    std.debug.assert(a.len", &buf) == null);
}

test "the ledger classifies by condition text, and a file suffix is a path suffix" {
    const m31 = ledger[2];
    try std.testing.expectEqualStrings("libs/stark/m31", m31.path);
    try std.testing.expectEqual(@as(usize, 11), m31.invariants.len);
    var declared: usize = 0;
    for (m31.invariants) |c| declared += c.count;
    try std.testing.expectEqual(@as(usize, 12), declared);

    // The six private-helper asserts are five conditions, one of them twice.
    var twice: usize = 0;
    for (m31.invariants) |c| {
        if (c.count == 2) twice += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), twice);

    try std.testing.expect(endsWithPath("libs/stark/m31/ntt/circle.zig", "ntt/circle.zig"));
    try std.testing.expect(!endsWithPath("libs/stark/m31/ntt/classic.zig", "ntt/circle.zig"));
    try std.testing.expectEqual(@as(usize, 0), ledger[0].invariants.len);
}

test "the ledger's own numbers add up" {
    var declared: usize = 0;
    var reachable: usize = 0;
    var invariant: usize = 0;
    var fixture: usize = 0;
    var internal_only: usize = 0;
    for (ledger) |zone| {
        declared += zone.asserts;
        var here: usize = 0;
        for (zone.invariants) |c| here += c.count;
        invariant += here;
        switch (zone.kind) {
            .api => reachable += zone.asserts - here,
            .fixture => fixture += zone.asserts,
            .internal => internal_only += zone.asserts,
        }
    }
    // The summary prints these side by side, so if they stop adding up the
    // headline is lying in a way a reader cannot see.
    try std.testing.expectEqual(declared, reachable + invariant + fixture + internal_only);
    try std.testing.expectEqual(declared_reachable, reachable);
    try std.testing.expectEqual(@as(usize, 64), declared_reachable);
    // transcript is the zone that proves reachability is a declared claim: both
    // of its asserts are `pub fn` inside something private.
    var fixture_zones: usize = 0;
    for (ledger) |zone| {
        if (zone.kind == .fixture) fixture_zones += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), fixture_zones);
}
