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
//!      ledger with a reason and a trigger to resolve it.
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

/// A zone is a subtree of `libs/` whose relationship to `zig-algebra` is written
/// down. `upstream` is null when the zone has no counterpart over there, which
/// is a legitimate state and still gets a declared assert count: the rule that
/// matters is the count, not the duplication.
const Zone = struct {
    path: []const u8,
    upstream: ?[]const u8,
    asserts: usize,
    reason: []const u8,
    revisit: []const u8,
};

const ledger = [_]Zone{
    .{
        .path = "libs/stark/binius",
        .upstream = "zig-algebra/libs/binary-field @ 0.3.2",
        .asserts = 81,
        .reason = "binius is the original. zig-algebra/libs/binary-field/src/root.zig " ++
            "says it was 'Extracted from zig-stark's binius implementation', and six " ++
            "files are byte-identical to that release. The extraction was hardened " ++
            "in 0.4.0 and published; this copy was never re-adopted, so it still " ++
            "carries the pre-hardening inversions (field.zig inv, tower.zig inv) " ++
            "that 0.4.0 replaced with invChecked.",
        .revisit = "adopt zig-binary-field for the field, tower, pack, polynomial, " ++
            "clmul and accel files, and re-derive pcs and sumcheck on top of it",
    },
    .{
        .path = "libs/stark/core",
        .upstream = null,
        .asserts = 2,
        .reason = "merkle and serialization are local implementations shaped for " ++
            "the prover's own column layout, not the generic trees in " ++
            "zig-merkle and zig-serialization. They share four API names each and " ++
            "no code, so this is a parallel implementation rather than a copy.",
        .revisit = "revisit if a consumer outside this repository needs the " ++
            "prover's column layout, or if a generic tree can serve it",
    },
    .{
        .path = "libs/stark/m31",
        .upstream = null,
        .asserts = 37,
        .reason = "the M31 circle STARK has no counterpart in zig-algebra; " ++
            "zig-algebra's FRI is a radix-2 FRI over a base-field subgroup and " ++
            "M31's two-adicity is 1, so it cannot be used here. The zone is " ++
            "legitimately local and the count is a plain debt against the " ++
            "AGENTS.md rule.",
        .revisit = "convert to typed errors, following the pattern 0.4.0 " ++
            "established in zig-algebra's own field and ntt",
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
            while (lines.next()) |line| {
                const code = codeOf(line);
                scanCodeForImports(code, &imports);
                for (ledger, 0..) |zone, zi| {
                    if (!std.mem.startsWith(u8, path, zone.path)) continue;
                    zone_asserts[zi] += countOccurrences(code, assert_token);
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
                "AGENTS.md forbids them on the public API, which libs/stark/root.zig " ++
                "re-exports. Revert the addition or record it deliberately", .{
                zone.path, zone_asserts[zi], zone.asserts,
            });
        } else {
            p.setDetail("{s} has {d} std.debug.assert, the ledger declares {d}: the " ++
                "count improved, record it in scripts/check_contract.zig so the " ++
                "ledger stays exact", .{ zone.path, zone_asserts[zi], zone.asserts });
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

    std.debug.print(
        "contract check passed: {d} files, {d} algebra modules, pin {s}, " ++
            "{d} zones at their declared assert counts\n",
        .{ files_scanned, imports.algebra.items.len, declared_algebra_pin, ledger.len },
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
