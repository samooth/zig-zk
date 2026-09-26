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

/// A private function whose asserts are carved out of the zone's public count.
const InternalFn = struct {
    /// Suffix of the path, so one function name in two files stays two
    /// functions.
    file: []const u8,
    name: []const u8,
};

/// A zone is a subtree of `libs/` whose relationship to `zig-algebra` is written
/// down. `upstream` is null when the zone has no counterpart over there, which
/// is a legitimate state and still gets a declared assert count: the rule that
/// matters is the count, not the duplication.
///
/// `asserts` is the whole zone and `internal_asserts` is the part of it that
/// lives in the named private helpers. The difference is the number a caller can
/// reach, which is the number that was being argued about instead of read. Both
/// are ratcheted the same way.
const Zone = struct {
    path: []const u8,
    kind: Kind,
    upstream: ?[]const u8,
    asserts: usize,
    internal_fns: []const InternalFn,
    internal_asserts: usize,
    reason: []const u8,
    revisit: []const u8,
};

const ledger = [_]Zone{
    .{
        .path = "libs/stark/binius",
        .kind = .api,
        .upstream = "zig-algebra/libs/binary-field @ 0.3.2",
        .asserts = 81,
        .internal_fns = &.{},
        .internal_asserts = 0,
        .reason = "binius is the original. zig-algebra/libs/binary-field/src/root.zig " ++
            "says it was 'Extracted from zig-stark's binius implementation'. Three " ++
            "files are byte-identical to 0.3.2 (accel, clmul, polynomial); field, " ++
            "pack and tower differ only by the invChecked work this repository " ++
            "did, which 0.4.0 also carries. 61 of the 81 are on public functions " ++
            "and 20 sit in private helpers spread over adder, bitpack, compare, " ++
            "pack, packed_pcs, rangecheck, poseidon2b, stark and sumcheck. That " ++
            "split is prose and not a carve-out because the zone is about to be " ++
            "replaced by the upstream module, and a sixteen-name list would be " ++
            "dead weight by then.",
        .revisit = "replaced-by-upstream: adopt zig-binary-field and delete this " ++
            "zone, but adoption does not close the characteristic-2 hole, it " ++
            "moves the zone. Four functions in four files assume characteristic " ++
            "two: polynomial.zig eval and extend fold a pair as a + r*(a + b) " ++
            "where the identity is a + r*(b - a), sumcheck.zig interpolateCoeffs " ++
            "builds the Lagrange denominator with points[i] + points[j], pack.zig " ++
            "lagrangeBasis divides by (x + x_i), and pcs.zig builds the kernel as " ++
            "t + (1 + r_j). Over a prime field of 128 bits or more all four " ++
            "compile and return garbage, and the fold is the entry point, so a " ++
            "misuse hits it before the interpolation. The PR in flight upstream " ++
            "fixes interpolateCoeffs and lagrangeBasis, which are no-ops in " ++
            "characteristic two; the fold and the kernel are not in it. Treat " ++
            "that as an input to the adoption decision, not as a detail. " ++
            "Separately, the local invChecked returns error.DivideByZero where " ++
            "upstream returns error.InverseOfZero, so the six call sites follow " ++
            "upstream's name. Nothing here is waiting to become an error union.",
    },
    .{
        .path = "libs/stark/core",
        .kind = .api,
        .upstream = null,
        .asserts = 2,
        .internal_fns = &.{},
        .internal_asserts = 0,
        .reason = "merkle and serialization are local implementations shaped for " ++
            "the prover's own column layout, not the generic trees in " ++
            "zig-merkle and zig-serialization. They share four API names each and " ++
            "no code, so this is a parallel implementation rather than a copy. " ++
            "Both asserts are on the public surface (MerkleTree init and open), " ++
            "so the kind is api: local describes the missing upstream counterpart, " ++
            "not the reachability of the asserts.",
        .revisit = "revisit if a consumer outside this repository needs the " ++
            "prover's column layout, or if a generic tree can serve it",
    },
    .{
        .path = "libs/stark/m31",
        .kind = .api,
        .upstream = null,
        .asserts = 37,
        .internal_fns = &.{
            .{ .file = "ntt/circle.zig", .name = "interleave" },
            .{ .file = "ntt/circle.zig", .name = "deinterleave" },
            .{ .file = "ntt/circle.zig", .name = "slowPrecomputeTwiddles" },
            .{ .file = "ntt/circle.zig", .name = "getFoldingAlphas" },
        },
        .internal_asserts = 6,
        .reason = "the M31 circle STARK has no counterpart in zig-algebra; " ++
            "zig-algebra's FRI is a radix-2 FRI over a base-field subgroup and " ++
            "M31's two-adicity is 1, so it cannot be used here. The zone is " ++
            "legitimately local and the count is a debt against the AGENTS.md " ++
            "rule. 31 of the 37 are on public functions; the 6 carved out sit in " ++
            "four private helpers in ntt/circle.zig that the public entry points " ++
            "call with arguments they have already checked, so they are " ++
            "invariants between two internal calls rather than caller input.",
        .revisit = "the 31 are the work: convert them to typed errors, following " ++
            "the pattern 0.4.0 established in zig-algebra's own field and ntt. " ++
            "prove and proveCodeword are in the prover's hot path and changing " ++
            "their signatures is a public API change, so they get their own " ++
            "commit and a changelog entry rather than a step in the ratchet. The " ++
            "6 stay as they are unless a caller can reach them.",
    },
    .{
        .path = "libs/transcript",
        .kind = .fixture,
        .upstream = null,
        .asserts = 2,
        .internal_fns = &.{},
        .internal_asserts = 0,
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
        .internal_fns = &.{},
        .internal_asserts = 0,
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
        .internal_fns = &.{},
        .internal_asserts = 0,
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
        .internal_fns = &.{},
        .internal_asserts = 0,
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
    "zig-curve",
    "zig-field",
    "zig-hash",
    "zig-merkle",
    "zig-pairing",
    "zig-poly",
};

/// Modules this repository owns. Listed so that a typo in one of them is
/// reported as a boundary change rather than as a mysteriously missing import.
const declared_own_modules = [_][]const u8{
    "zig-stark",
    "zig-transcript",
};

/// The version every manifest that declares `zig_algebra` must pin.
const declared_algebra_pin = "0.3.2";

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
const declared_reachable: usize = 114;

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
const fn_keyword = "fn ";

/// The name in a function declaration on this line, if it declares one.
///
/// Null when the line has no `fn`, and also when `fn` is a function *type*
/// (`const g: fn (u8) void`), which the empty-name case catches. A declaration
/// the scanner cannot name returns null, and a null leaves its asserts in the
/// public count: the wrong answer, but the conservative one, because it
/// overstates what a caller can reach rather than hiding it.
fn declaredFnName(code: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, code, fn_keyword) orelse return null;
    const rest = code[at + fn_keyword.len ..];
    const end = std.mem.indexOfAny(u8, rest, " \t(<{") orelse return null;
    if (end == 0) return null;
    return rest[0..end];
}

/// Whether an assert in `path` inside `enclosing` is one of the zone's carved
/// out private helpers. The file is matched as a path suffix so the same
/// function name in two files stays two functions.
fn isCarvedOut(zone: Zone, path: []const u8, enclosing: []const u8) bool {
    for (zone.internal_fns) |f| {
        if (!std.mem.eql(u8, f.name, enclosing)) continue;
        if (std.mem.endsWith(u8, path, f.file)) return true;
    }
    return false;
}

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
    var internal_asserts = [_]usize{0} ** ledger.len;
    var files_scanned: usize = 0;

    // Rule 4. Every manifest that names the dependency must pin the same
    // version, or the build and the ledger disagree about what is being consumed.
    {
        const manifests = [_][]const u8{
            "build.zig.zon",
            "libs/stark/build.zig.zon",
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
            // Which `fn` the current line belongs to, so a zone can carve its
            // private helpers out of the public count. Reset per file: the
            // scanner is line based, and a stale name from the previous file
            // would silently move asserts between buckets.
            var enclosing: []const u8 = "";
            while (lines.next()) |line| {
                const code = codeOf(line);
                scanCodeForImports(code, &imports);
                if (declaredFnName(code)) |name| enclosing = name;
                const found = countOccurrences(code, assert_token);
                if (found == 0) continue;
                for (ledger, 0..) |zone, zi| {
                    if (!std.mem.startsWith(u8, path, zone.path)) continue;
                    zone_asserts[zi] += found;
                    if (isCarvedOut(zone, path, enclosing)) internal_asserts[zi] += found;
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

    // Rule 2, second number. The carved out helpers are ratcheted separately so
    // that "the zone's size moved" and "the reachable part moved" cannot be
    // confused. The first is the zone, the second is the debt anyone can act on.
    for (ledger, 0..) |zone, zi| {
        if (zone.internal_fns.len == 0) continue;
        if (internal_asserts[zi] == zone.internal_asserts) continue;
        var p: Problem = .{};
        p.setWhat("internal asserts", .{});
        if (internal_asserts[zi] > zone.internal_asserts) {
            p.setDetail("{s} has {d} std.debug.assert in the private helpers it " ++
                "carves out, the ledger declares {d}. Either the helper gained an " ++
                "assert or one of them was renamed, which moves its asserts into " ++
                "the public count: check the names in internal_fns", .{
                zone.path, internal_asserts[zi], zone.internal_asserts,
            });
        } else {
            p.setDetail("{s} has {d} std.debug.assert in the private helpers it " ++
                "carves out, the ledger declares {d}: record the new number, and " ++
                "whether the helper stays carved out", .{
                zone.path, internal_asserts[zi], zone.internal_asserts,
            });
        }
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
                reachable += zone.asserts - internal_asserts[zi];
                carved_out += internal_asserts[zi];
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
    std.debug.print(
        "contract check passed: {d} files, {d} algebra modules, pin {s}, " ++
            "{d} zones at their declared assert counts; {d} declared = " ++
            "{d} reachable + {d} carved out + {d} fixture + {d} internal-only\n",
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

test "declaredFnName names a declaration and nothing else" {
    try std.testing.expectEqualStrings("circleFFT", declaredFnName("pub fn circleFFT(").?);
    try std.testing.expectEqualStrings("interleave", declaredFnName("fn interleave(").?);
    try std.testing.expectEqualStrings("add", declaredFnName("    pub fn add(self: M31, other: M31) M31 {").?);

    // A function type is not a declaration.
    try std.testing.expect(declaredFnName("const g: fn (u8) void = undefined;") == null);
    try std.testing.expect(declaredFnName("const Cb = struct { fn (u8) void };") == null);

    // Nothing to name.
    try std.testing.expect(declaredFnName("    std.debug.assert(a.len == b.len);") == null);
    try std.testing.expect(declaredFnName("") == null);
}

test "a carved out helper is matched by file and name together" {
    const m31 = ledger[2];
    try std.testing.expectEqualStrings("libs/stark/m31", m31.path);
    try std.testing.expectEqual(@as(usize, 4), m31.internal_fns.len);
    try std.testing.expectEqual(@as(usize, 6), m31.internal_asserts);

    // The carve out needs both the file suffix and the name.
    try std.testing.expect(isCarvedOut(
        m31,
        "libs/stark/m31/ntt/circle.zig",
        "interleave",
    ));
    try std.testing.expect(!isCarvedOut(
        m31,
        "libs/stark/m31/ntt/circle.zig",
        "circleFFT",
    ));
    try std.testing.expect(!isCarvedOut(
        m31,
        "libs/stark/m31/ntt/classic.zig",
        "interleave",
    ));

    // A zone with nothing carved out never matches.
    try std.testing.expectEqual(@as(usize, 0), ledger[0].internal_fns.len);
    try std.testing.expect(!isCarvedOut(
        ledger[0],
        "libs/stark/m31/ntt/circle.zig",
        "interleave",
    ));
}

test "the ledger declares a kind for every zone, and a reachable count" {
    for (ledger) |zone| {
        try std.testing.expect(zone.asserts >= zone.internal_asserts);
        try std.testing.expect(zone.reason.len > 0);
        try std.testing.expect(zone.revisit.len > 0);
    }
    // transcript is the zone that proves reachability is a declared claim: both
    // of its asserts are `pub fn` inside something private.
    var fixture: usize = 0;
    var clean: usize = 0;
    for (ledger) |zone| {
        if (zone.kind == .fixture) fixture += 1;
        if (zone.kind == .api and zone.asserts == 0) clean += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), fixture);
    try std.testing.expectEqual(@as(usize, 3), clean);
}

test "the ledger's own numbers add up" {
    var declared: usize = 0;
    var reachable: usize = 0;
    var carved: usize = 0;
    var fixture: usize = 0;
    var internal_only: usize = 0;
    for (ledger) |zone| {
        declared += zone.asserts;
        switch (zone.kind) {
            .api => {
                try std.testing.expect(zone.asserts >= zone.internal_asserts);
                reachable += zone.asserts - zone.internal_asserts;
                carved += zone.internal_asserts;
            },
            .fixture => fixture += zone.asserts,
            .internal => internal_only += zone.asserts,
        }
    }
    // The summary prints these four numbers side by side, so if they stop
    // adding up the headline is lying in a way a reader cannot see.
    try std.testing.expectEqual(declared, reachable + carved + fixture + internal_only);
    try std.testing.expectEqual(declared_reachable, reachable);
    try std.testing.expectEqual(@as(usize, 114), declared_reachable);
}
