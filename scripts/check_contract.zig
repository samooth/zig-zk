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
        .upstream = null,
        .asserts = 57,
        .invariants = &.{},
        .reason = "this zone is no longer a fork of zig-algebra. Six files were " ++
            "adopted from it, then the sum-check and the PCS, and with them " ++
            "accel.zig and core/pool.zig: the sum-check was confirmed " ++
            "byte-identical to the adopted one over value, claimed sum and six " ++
            "rounds, and the PCS was not, because our commit hashed every Merkle " ++
            "leaf twice while the adopted convention hashes it once. What " ++
            "remains here is twelve files with no upstream counterpart at all " ++
            "-- the Binius circuits, the FRI and batch commitment schemes, the " ++
            "argument layer and the prover. Upstream has no fripcs, no " ++
            "batchpcs, no arg: a zone can stop being a fork without ceasing to " ++
            "exist, and this is that case. 57 asserts, none of them classified, " ++
            "so every one counts as reachable and overstates the work.",
        .revisit = "two entries, both about coverage rather than code. " ++
            "The 128-bit gate is on the extension field, not the base one, " ++
            "because the sum-check runs over the extension: SC = Sumcheck(E). " ++
            "Gf256 as an extension is eight bits, so the gadget fuzz needs the " ++
            "Unsafe variants, and a sum-check round there has a soundness " ++
            "error of order 1/|F|. The rounds add rather than compound: the " ++
            "total is a sum bound of order k/|F| for k rounds, not a product, " ++
            "so a narrow field is paid for once per round and no round count " ++
            "rescues an eight-bit extension. k belongs to the caller: the prover " ++
            "runs exactly that many sum-check rounds, the verifier checks the " ++
            "count, and measured over eight bits and 128 the count is the same, " ++
            "because it comes from the call and not from the field. So there is " ++
            "no single k to quote, and the field is what binds: one round over " ++
            "eight bits costs 2^-8, which no choice of k makes 2^-128. That is " ++
            "why the secure entry point gates on bits of field and not on a " ++
            "round count. Binius also " ++
            "commits in a bilinear algebra rather than a field, so a " ++
            "prime-field soundness argument does not carry over verbatim. " ++
            "Read that suite as coverage of plumbing, not of soundness. " ++
            "TowerField(7) is " ++
            "128 bits, is instantiated -- the whole prover runs as " ++
            "BiniusStark(Gf16, Gf2_128), and so do the packed PCS and the " ++
            "recursion -- and those call sites use the secure entry points, " ++
            "because they pass the gate. The destination is exercised; what is " ++
            "missing is that it is the exception, since the fuzz a reader runs " ++
            "is over eight bits. It now runs a second, smaller pass over the " ++
            "128-bit pair, and the claim that makes is that the path gets " ++
            "random witnesses, not that it is sound. The bound is a sum and not " ++
            "a product: a round's error is of order 1/|F| and k rounds give " ++
            "order k/|F|, so an eight-bit extension is paid for once per round " ++
            "and no round count rescues it. k belongs to the caller rather than " ++
            "to the prover, the verifier checks the round count against it, and " ++
            "the count does not depend on the field: measured over eight bits " ++
            "and 128 it is the same. There is no single k to quote, and the " ++
            "field is the constraint that binds. One further caveat, and it " ++
            "applies to the argument above rather than " ++
            "to the code: Binius commits in a bilinear algebra rather than a " ++
            "field, so a prime-field soundness argument does not carry over " ++
            "verbatim. " ++
            "Which multiplication the tower runs is a property of the host: " ++
            "mulFast on x86_64 with PCLMULQDQ, mulRec everywhere else, decided " ++
            "at comptime. So the CI matrix is the only thing covering both, by " ++
            "its shape: ubuntu-latest and windows-latest are x86_64 and take " ++
            "mulFast, macos-latest is arm64 and takes mulRec. Change a runner " ++
            "and that coverage narrows with nothing failing, which is why it is " ++
            "here. Note the two are less independent than it looks: mulFast " ++
            "builds its conversion and reduction tables by calling mulRec, so " ++
            "the Karatsuba is on the path of the bit-sliced multiply on every " ++
            "host, and a defect in it reaches both. The cross-implementation " ++
            "test in tests/tower_mul.zig therefore buys one narrow thing -- " ++
            "catching a defect one has and the other does not, at the level of " ++
            "the product -- and cannot catch the two being wrong together, " ++
            "because agreement is not correctness. Removing that test does not " ++
            "lose a check; it loses the only place the two are compared. Revisit " ++
            "if the matrix changes, and record the new geometry.",
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
        .asserts = 1,
        .invariants = &.{
            // An invariant of the test adapter, not a precondition a caller can
            // violate: `CurveScalar` cannot hold a non-canonical scalar, because
            // fromBytes rejects one, fromInt reduces, and add and mul of scalars
            // below the order stay below it. The assert stands where a `catch`
            // used to return the point at infinity, which is the value that
            // makes Schnorr verification degenerate into `s*G == R`. A typed
            // error here would mean a fallible signature on the adapter for a
            // case its own constructors forbid.
            .{ .file = "src/root.zig", .condition = "false and \"CurveScalar holds a non-canonical scalar\"" },
        },
        .reason = "Ed25519 is std's, and the one assert is an adapter invariant " ++
            "rather than a precondition. Recorded so that a new assert has to be " ++
            "declared rather than added.",
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
const declared_algebra_pin = "0.6.0";

/// The committed listing of published `zig-algebra` tags. This path is the
/// reference Rule 6 compares against, and it is a file rather than a network
/// call on purpose.
const algebra_tags_path = "scripts/algebra-tags.txt";

const PinVerdict = union(enum) {
    ok,
    empty_reference,
    malformed,
    not_published,
    too_far_behind,
};

/// The newest tag in a listing, or "" when there is none. Comments and blank
/// lines are not tags, so a listing that documents itself does not make the
/// gate read its own documentation as the newest release.
fn newestInListing(listing: []const u8) []const u8 {
    var newest: []const u8 = "";
    var it = std.mem.splitScalar(u8, listing, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (t[0] != 'v' or t.len < 3 or !std.ascii.isDigit(t[1])) continue;
        newest = t[1..];
    }
    return newest;
}

/// Where the pin sits in the published listing. Pure, so the interesting cases
/// are testable without the filesystem, and there are three of them: the gap in
/// algebra's history between v0.3.2 and v0.5.1, a listing edited by hand, and a
/// pin that names a release nobody published.
///
/// "One release behind" is a position in this list, not a subtraction. zig-algebra
/// published no v0.4.x and no v0.5.0, so 0.6.0 minus 0.5.3 is seven releases by
/// minor-and-patch arithmetic and one by publication. A version comparison here
/// would be a gate that fails on a healthy repository.
fn pinPosition(listing: []const u8, pin: []const u8) PinVerdict {
    var total: usize = 0;
    var found: ?usize = null;
    var malformed = false;
    var it = std.mem.splitScalar(u8, listing, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (t[0] != 'v' or t.len < 3 or !std.ascii.isDigit(t[1])) {
            malformed = true;
            continue;
        }
        total += 1;
        if (found == null and std.mem.eql(u8, t[1..], pin)) found = total - 1;
    }
    if (malformed) return .malformed;
    if (total == 0) return .empty_reference;
    const at = found orelse return .not_published;
    if (at + 2 < total) return .too_far_behind;
    return .ok;
}

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
const declared_reachable: usize = 60;

/// The total the root `test` step runs, as the architecture documents state it.
///
/// A number written by hand in a document goes stale and the next reader takes
/// it as true: this repository has had to correct a stale total here, a README
/// listing four files that no longer existed, and a ledger entry claiming nobody
/// had instantiated a field three call sites were instantiating. The fix is not
/// updating the figure, it is the figure not being hand-written. So the number
/// lives here, moves only when someone edits this line and says why, and the
/// documents are checked against it rather than trusted.
const declared_root_tests: usize = 289;

/// The unit-test count the stark README states, which is the other figure a
/// reader looks at. It is the root build's `zig-stark-tests` step and not the
/// standalone library build, which runs more: the standalone build also carries
/// the end-to-end, fuzz and known-answer suites, so it totals 185. Two plausible
/// numbers for the same library is how a figure like this goes stale without
/// anyone noticing, so the distinction is written here rather than left to the
/// sentence that uses it.
const declared_stark_unit_tests: usize = 162;

/// What the standalone stark build totals, which is the same library plus the
/// end-to-end, fuzz and known-answer suites. Declared so that the difference
/// between the two numbers is a fact here rather than an arithmetic coincidence
/// in a message: a reader who runs `cd libs/stark && zig build test` sees 185 and
/// a README that says 162, and the honest answer is which step each counts.
const declared_stark_standalone_tests: usize = 185;

const max_detail = 512;

/// Whether `path` is inside `prefix`, treating both separators as equal.
///
/// The gate used to compare raw walked paths against prefixes written with a
/// forward slash, which is why it reported a repository with no sources in it
/// on Windows: the paths there come back as `libs\stark\...`. The collector
/// below already joins with `/`, so this is the second line of defence, and it
/// is the one that can be tested from a platform that does not have the
/// problem.
fn pathUnder(path: []const u8, prefix: []const u8) bool {
    if (path.len < prefix.len) return false;
    for (prefix, 0..) |c, i| {
        const got = path[i];
        const want = if (got == '\\') '/' else got;
        if (want != c) return false;
    }
    if (path.len == prefix.len) return true;
    // A prefix that does not end at a separator has to end at one, or
    // `libs/stark` would match `libs/starkly`. A prefix that already ends in a
    // separator is a directory, and it has no boundary to check.
    if (prefix[prefix.len - 1] == '/' or prefix[prefix.len - 1] == '\\') return true;
    return path[prefix.len] == '/' or path[prefix.len] == '\\';
}

/// Every file under `root`, recursively, as paths relative to it and always
/// separated by `/`. Directories that are a package cache, a build cache or a
/// version-control directory are not descended into.
fn collectSources(
    alloc: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    prefix: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var dir = cwd.openDir(io, if (prefix.len == 0) "." else prefix, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (std.mem.eql(u8, entry.name, "zig-pkg")) continue;
                if (std.mem.eql(u8, entry.name, ".zig-cache")) continue;
                if (std.mem.eql(u8, entry.name, ".git")) continue;
                if (std.mem.eql(u8, entry.name, ".opencode")) continue;
                const child = if (prefix.len == 0)
                    try alloc.dupe(u8, entry.name)
                else
                    try std.fmt.allocPrint(alloc, "{s}/{s}", .{ prefix, entry.name });
                try collectSources(alloc, io, cwd, child, out);
            },
            else => {
                const child = if (prefix.len == 0)
                    try alloc.dupe(u8, entry.name)
                else
                    try std.fmt.allocPrint(alloc, "{s}/{s}", .{ prefix, entry.name });
                try out.append(alloc, child);
            },
        }
    }
}

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

/// A module name wired into a build file: `addImport("name", ...)` or
/// `.module("name")`.
fn scanCodeForWiring(code: []const u8, sink: *std.ArrayList([]const u8), alloc: std.mem.Allocator) void {
    var lines = std.mem.splitScalar(u8, code, '\n');
    while (lines.next()) |line| {
        const body = codeOf(line);
        for ([_][]const u8{ "addImport(", ".module(" }) |call| {
            const at = std.mem.indexOf(u8, body, call) orelse continue;
            const after = at + call.len;
            const open = std.mem.indexOfScalar(u8, body[after..], '"') orelse continue;
            const from = after + open + 1;
            const close = std.mem.indexOfScalar(u8, body[from..], '"') orelse continue;
            const name = body[from .. from + close];
            if (name.len == 0) continue;
            var seen = false;
            for (sink.items) |old| {
                if (std.mem.eql(u8, old, name)) seen = true;
            }
            if (!seen) sink.append(alloc, name) catch return;
        }
    }
}

/// Rule 5, the direction Rule 3 does not look at: a module wired into a build
/// that nothing imports.
///
/// Rule 3 starts from what the sources import, so a module no source imports
/// never enters it. `zig-rng` sat wired into two libraries' `build.zig` with no
/// `.zig` anywhere importing it, and every existing rule passed. A wired module
/// that no source imports is not dead weight, it is a dependency the audit
/// believes is in use -- which is exactly how a third-party module goes unaudited
/// while the manifest says it is wired.
fn reportUnwired(
    problems: *std.ArrayList(Problem),
    alloc: std.mem.Allocator,
    wired: []const []const u8,
    imports: *const Imports,
) !void {
    for (wired) |name| {
        var used = false;
        for (imports.algebra.items) |x| {
            if (std.mem.eql(u8, x, name)) used = true;
        }
        for (imports.own.items) |x| {
            if (std.mem.eql(u8, x, name)) used = true;
        }
        if (used) continue;
        var p: Problem = .{};
        p.setWhat("wiring", .{});
        p.setDetail("a build file wires {s} but no file under libs/ imports it: " ++
            "a wired module the audit believes is in use is a module nobody audits", .{name});
        try problems.append(alloc, p);
    }
}

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
/// The unit-test count the stark README states, if it states one.
fn statedUnitTestTotal(text: []const u8) ?usize {
    const markers = [_][]const u8{ " unit tests here", " pruebas unitarias aquí" };
    for (markers) |marker| {
        const at = std.mem.indexOf(u8, text, marker) orelse continue;
        var i = at;
        while (i > 0 and (text[i - 1] == ' ' or text[i - 1] == '\n')) i -= 1;
        const end = i;
        while (i > 0 and std.ascii.isDigit(text[i - 1])) i -= 1;
        if (i == end) continue;
        return std.fmt.parseInt(usize, text[i..end], 10) catch null;
    }
    return null;
}

/// The test total a document states, if it states one.
///
/// Deliberately narrow: it looks for the total the root step runs, written as
/// the count right before the word for "tests" followed by the enumeration of the
/// suites, or its Spanish counterpart. A document that stops saying it is a
/// failure for the caller to hear about, not something to treat as zero.
fn statedTestTotal(text: []const u8) ?usize {
    // Both documents say the same thing at the same point in the sentence, and
    // the figure is what immediately follows it: "runs every suite: 248 tests"
    // and "todas las suites: 248 pruebas". Anchoring there rather than on the
    // enumeration keeps it independent of where either one wraps, which is what
    // let the Spanish figure drift while the English one was corrected.
    const markers = [_][]const u8{ "every suite:", "las suites:" };
    for (markers) |marker| {
        const at = std.mem.lastIndexOf(u8, text, marker) orelse continue;
        var i = at + marker.len;
        while (i < text.len and (text[i] == ' ' or text[i] == '\n')) i += 1;
        const start = i;
        while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
        if (i == start) continue;
        return std.fmt.parseInt(usize, text[start..i], 10) catch null;
    }
    return null;
}

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
    var manifests_read: usize = 0;
    var test_files: std.ArrayList([]const u8) = .empty;
    defer test_files.deinit(alloc);

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
        // A gate that reads no manifest must say so. Skipping a manifest it
        // cannot open is right; skipping every one of them and reporting nothing
        // is how this gate once reported every zone at zero asserts in CI while
        // passing here, because the two runs had different working directories
        // and the difference was invisible in the output.
        for (manifests) |path| {
            const text = readOrNull(alloc, io, path) orelse continue;
            manifests_read += 1;
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

    // Rule 6. The pin has to be a tag that was actually published, and no more
    // than one release behind the newest one. The reference is the committed
    // listing in `scripts/algebra-tags.txt`, never the network: a gate that
    // reaches for `git ls-remote` gives a different answer in CI than it does on
    // a laptop, and a gate that sometimes knows is not a gate.
    //
    // This rule has a threshold and a reference, which is the pair the earlier
    // rules were missing. Rule 4 compares the six manifests against the ledger
    // and both could be moved together without anyone noticing; this one reaches
    // outside the repository, to a list that only a person can refresh.
    // The listing outlives the verdict on purpose. `newest_tag` is a slice into
    // it, and freeing the buffer inside the block that computes the verdict left
    // the message pointing at freed memory -- which the mutation test caught as a
    // row of replacement characters. A gate that fires with an unreadable
    // diagnosis is half a gate: the exit code says what happened and the text
    // says nothing.
    const listing = readOrNull(alloc, io, algebra_tags_path);
    defer if (listing) |t| alloc.free(t);
    var newest_tag: []const u8 = "";
    const pin_verdict = if (listing) |text| blk: {
        newest_tag = newestInListing(text);
        break :blk pinPosition(text, declared_algebra_pin);
    } else .empty_reference;
    {
        switch (pin_verdict) {
            .ok => {},
            .empty_reference, .malformed => {
                var p: Problem = .{};
                p.setWhat("pin-age", .{});
                p.setDetail("the listing at {s} is not a usable reference: it has " ++
                    "no tag in it, or a line that is not one. Run " ++
                    "`zig build refresh-algebra-tags`. A threshold with a reference " ++
                    "that cannot be read is a gate that passes always", .{algebra_tags_path});
                try problems.append(alloc, p);
            },
            .not_published => {
                var p: Problem = .{};
                p.setWhat("pin-age", .{});
                p.setDetail("the pin is zig-algebra {s} and the listing at {s} does " ++
                    "not contain it, so the pin names a release that was never " ++
                    "published. An unpublished pin is not a pin; run " ++
                    "`zig build refresh-algebra-tags`", .{ declared_algebra_pin, algebra_tags_path });
                try problems.append(alloc, p);
            },
            .too_far_behind => {
                var p: Problem = .{};
                p.setWhat("pin-age", .{});
                p.setDetail("the pin is zig-algebra {s} and the newest published is " ++
                    "{s}, which is more than one release back. That is how the dead " ++
                    "PRNG survived three signed releases of a dependency", .{
                    declared_algebra_pin,
                    newest_tag,
                });
                try problems.append(alloc, p);
            },
        }
    }

    if (manifests_read == 0) {
        var p: Problem = .{};
        p.setWhat("root", .{});
        p.setDetail("no build.zig.zon could be read from the working directory, so " ++
            "this gate is not looking at the repository. It would otherwise " ++
            "report every zone at zero and every module unused", .{});
        try problems.append(alloc, p);
    }

    // Rules 2 and 3. One pass over the source.
    {
        const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
        defer cwd.close(io);

        var all: std.ArrayList([]const u8) = .empty;
        defer {
            for (all.items) |p| alloc.free(p);
            all.deinit(alloc);
        }
        try collectSources(alloc, io, cwd, "", &all);

        for (all.items) |path| {
            if (!std.mem.endsWith(u8, path, ".zig")) continue;
            if (!pathUnder(path, "libs/")) continue;
            if (pathUnder(path, "libs/stark/tests/")) {
                // The path itself belongs to the collector's arena, which is
                // released with that block. Keep the name, not the slice into a
                // buffer that is about to go: the first version of this rule
                // printed freed memory.
                try test_files.append(alloc, try alloc.dupe(u8, std.fs.path.basename(path)));
            }

            const text = cwd.readFileAlloc(io, path, alloc, .limited(1 << 22)) catch continue;
            files_scanned += 1;

            var lines = std.mem.splitScalar(u8, text, '\n');
            var cond_buf: [512]u8 = undefined;
            while (lines.next()) |line| {
                const code = codeOf(line);
                scanCodeForImports(code, &imports);
                if (countOccurrences(code, assert_token) == 0) continue;
                for (ledger, 0..) |zone, zi| {
                    if (!pathUnder(path, zone.path)) continue;
                    zone_asserts[zi] += countOccurrences(code, assert_token);
                }
                // Second pass over the ledger for the classification, because the
                // condition is only worth extracting for zones that name it.
                const condition = conditionOf(code, &cond_buf) orelse continue;
                for (ledger, 0..) |zone, zi| {
                    if (!pathUnder(path, zone.path)) continue;
                    for (zone.invariants) |c| {
                        if (!endsWithPath(path, c.file)) continue;
                        if (std.mem.eql(u8, c.condition, condition)) {
                            classified_found[zi] += 1;
                        }
                    }
                }
            }
        }

        // Rule 5, collected in the same pass that reads the sources: the builds
        // say what is wired, the sources say what is imported, and the two have
        // to meet. Rule 3 checks the other direction and, starting from the
        // sources, cannot see a module nothing imports.
        {
            var wired: std.ArrayList([]const u8) = .empty;
            defer wired.deinit(alloc);
            for (all.items) |path| {
                if (!endsWithPath(path, "build.zig")) continue;
                const text = readOrNull(alloc, io, path) orelse continue;
                scanCodeForWiring(text, &wired, alloc);
            }
            // `imports` was collected from libs/ only, which is the right
            // scope for Rule 3 but the wrong one here: "nobody imports it" has
            // to mean nobody in the repository, and the consumer in consumer/
            // is exactly who imports the five published modules. Collecting them
            // again from every .zig under the root is what keeps the three
            // public modules from reading as wired-and-abandoned.
            var used: std.ArrayList([]const u8) = .empty;
            defer used.deinit(alloc);
            var probe: Imports = .{ .alloc = alloc };
            for (all.items) |path| {
                if (!std.mem.endsWith(u8, path, ".zig")) continue;
                const text = readOrNull(alloc, io, path) orelse continue;
                scanCodeForImports(text, &probe);
            }
            try reportUnwired(&problems, alloc, wired.items, &probe);
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

    // Rule 6. The total the architecture documents quote is this constant, not
    // a figure typed into prose. A document that disagrees is a claim that has
    // gone stale, which is the failure this exists to catch rather than to
    // report.
    for ([_][]const u8{ "docs/architecture.md", "docs/architecture.es.md" }) |doc_path| {
        const text = readOrNull(alloc, io, doc_path) orelse {
            var p: Problem = .{};
            p.setWhat("doc", .{});
            p.setDetail("{s} is missing, so the test total it states cannot be " ++
                "checked", .{doc_path});
            try problems.append(alloc, p);
            continue;
        };
        const found = statedTestTotal(text) orelse {
            var p: Problem = .{};
            p.setWhat("doc", .{});
            p.setDetail("{s} no longer states a test total, so this rule has " ++
                "nothing to compare: either the sentence moved or the figure " ++
                "was removed by hand", .{doc_path});
            try problems.append(alloc, p);
            continue;
        };
        if (found != declared_root_tests) {
            var p: Problem = .{};
            p.setWhat("doc", .{});
            p.setDetail("{s} states {d} tests, the ledger says {d}: the figure " ++
                "lives in scripts/check_contract.zig and the document is " ++
                "checked against it, so this is the pair disagreeing rather " ++
                "than a number to update in two places", .{
                doc_path,
                found,
                declared_root_tests,
            });
            try problems.append(alloc, p);
        }
    }

    // Rule 7. The stark README's unit-test count, checked the same way and for
    // the same reason as the total: a figure typed into prose has no way of
    // knowing the build moved.
    for ([_][]const u8{ "libs/stark/README.md", "libs/stark/README.es.md" }) |doc_path| {
        const text = readOrNull(alloc, io, doc_path) orelse {
            var p: Problem = .{};
            p.setWhat("readme", .{});
            p.setDetail("{s} is missing, so the count it states cannot be " ++
                "checked", .{doc_path});
            try problems.append(alloc, p);
            continue;
        };
        const found = statedUnitTestTotal(text) orelse {
            var p: Problem = .{};
            p.setWhat("readme", .{});
            p.setDetail("{s} no longer states a unit-test count, so this rule " ++
                "has nothing to compare: the sentence moved or the figure was " ++
                "removed by hand", .{doc_path});
            try problems.append(alloc, p);
            continue;
        };
        if (found != declared_stark_unit_tests) {
            var p: Problem = .{};
            p.setWhat("readme", .{});
            p.setDetail("{s} states {d} unit tests, the ledger says {d}: the " ++
                "figure lives in scripts/check_contract.zig and the README is " ++
                "checked against it. Note the standalone library build totals " ++
                "{d}, because it also runs the end-to-end, fuzz and " ++
                "known-answer suites; the figure stated here is the root " ++
                "build's unit-test step", .{
                doc_path,
                found,
                declared_stark_unit_tests,
                declared_stark_unit_tests + 23,
            });
            try problems.append(alloc, p);
        }
    }

    // Rule 8. Every file under `libs/stark/tests/` is named in the stark README,
    // in both languages. A figure can be checked against the build; a description
    // cannot be checked against anything, and the way that shows is a suite
    // existing without the README mentioning it. This one caught the README
    // saying two known-answer suites while there were three, and no count could
    // have, because both the count and the build were individually right.
    for ([_][]const u8{ "libs/stark/README.md", "libs/stark/README.es.md" }) |readme| {
        const text = readOrNull(alloc, io, readme) orelse continue;
        for (test_files.items) |path| {
            const base = std.fs.path.basename(path);
            if (std.mem.indexOf(u8, text, base) != null) continue;
            var p: Problem = .{};
            p.setWhat("readme", .{});
            p.setDetail("{s} runs {s} and {s} does not mention it: a suite " ++
                "that exists and is not named in the README is one nobody " ++
                "reading the documentation learns about", .{ readme, path, base });
            try problems.append(alloc, p);
        }
    }

    // Rule 9. The two files whose adoption is still open, in both directions.
    //
    // Rule 8 covers the test directory, so deleting a library file triggers
    // nothing and the README keeps naming a path that is gone. That is the
    // pending decision in this repository -- `core/hash` and `core/merkle` wait
    // on the same file-hash verification the field layer took -- so the failure
    // it would leave is the one this repository has been paying for: an open
    // question presented as settled, or a settled thing described as present.
    //
    // The general version of this, a two-directional check over the whole
    // inventory table, is deliberately not attempted here. That table mixes
    // directories, files, unprefixed paths, cells naming several files,
    // identifiers like `m31.stark.FibAir`, and one row that names a file which
    // does not exist on purpose because it is a signpost to the adopted
    // upstream. Checking it in both directions means restructuring it first,
    // which is a change to the documentation and not to a gate.
    for ([_][]const u8{ "libs/stark/README.md", "libs/stark/README.es.md" }) |readme| {
        const text = readOrNull(alloc, io, readme) orelse continue;
        // The token is what the README says, the path is what has to be on disk
        // for it to be true. The first version of this rule had one string for
        // both, which was relative to `libs/stark/` while the check ran from the
        // repository root: both sides read false, the two agreed, and the rule
        // passed without ever having looked. A gate that is inert looks exactly
        // like a gate that is satisfied.
        const pairs = [_]struct { token: []const u8, path: []const u8 }{
            .{ .token = "core/hash", .path = "libs/stark/core/hash/hash.zig" },
            .{ .token = "core/merkle", .path = "libs/stark/core/merkle/merkle.zig" },
        };
        for (pairs) |pair| {
            var present = true;
            std.Io.Dir.cwd().access(io, pair.path, .{}) catch {
                present = false;
            };
            const named = std.mem.indexOf(u8, text, pair.token) != null;
            if (present == named) continue;
            var p: Problem = .{};
            p.setWhat("readme", .{});
            p.setDetail("{s} {s} {s} but {s} does not say so: {s}", .{
                readme,
                if (present) "has" else "no longer has",
                pair.path,
                readme,
                if (present)
                    "the README does not mention a file that exists"
                else
                    "the README still names a file that is gone, and no rule " ++
                        "will notice except this one",
            });
            try problems.append(alloc, p);
        }
    }

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

test "the pin rule counts publication, not version arithmetic" {
    // The listing as committed, with algebra's real gap: no v0.4.x and no v0.5.0.
    const listing =
        "# published tags\n" ++
        "v0.1.0\nv0.2.0\nv0.3.1\nv0.3.2\n" ++
        "v0.5.1\nv0.5.2\nv0.5.3\nv0.6.0\n";

    // The newest is fine, and so is the one before it. Those two are seven and
    // one releases apart by minor-and-patch arithmetic, which is the whole reason
    // this is a position and not a subtraction.
    try std.testing.expectEqual(PinVerdict.ok, pinPosition(listing, "0.6.0"));
    try std.testing.expectEqual(PinVerdict.ok, pinPosition(listing, "0.5.3"));

    // Two back from the newest is the failure.
    try std.testing.expectEqual(PinVerdict.too_far_behind, pinPosition(listing, "0.5.2"));
}

test "the pin rule refuses a release nobody published" {
    const listing = "v0.5.3\nv0.6.0\n";
    try std.testing.expectEqual(PinVerdict.not_published, pinPosition(listing, "0.7.0"));
    try std.testing.expectEqual(PinVerdict.not_published, pinPosition(listing, "0.6.1"));
}

test "the pin rule refuses a reference it cannot read, in either way" {
    try std.testing.expectEqual(PinVerdict.empty_reference, pinPosition("", "0.6.0"));
    try std.testing.expectEqual(PinVerdict.empty_reference, pinPosition("# only comments\n", "0.6.0"));
    // A line that is not a tag makes the reference unusable rather than skipped.
    // Skipping it would be a zero read as an absence, which is the mistake this
    // repository has now made four times.
    try std.testing.expectEqual(PinVerdict.malformed, pinPosition("v0.6.0\nrelease candidate\n", "0.6.0"));
}

test "the newest tag ignores the listing's own documentation" {
    // A file that explains itself has comment lines. Reading one as a tag would
    // make the gate compare the pin against prose.
    const listing = "\\# v0.9.9 is mentioned here and is not a release\nv0.5.3\nv0.6.0\n";
    try std.testing.expectEqualStrings("0.6.0", newestInListing(listing));
    try std.testing.expectEqualStrings("", newestInListing("# nothing\n"));
}

test "the README's unit-test count is read in either language" {
    const english = "162 unit tests here, plus 16 end-to-end tests and three fuzz suites";
    try std.testing.expectEqual(@as(?usize, 162), statedUnitTestTotal(english));

    // The Spanish figure sits at the start of a sentence and the same marker
    // shape has to find it, which is the half that drifted last time.
    const spanish = "162 pruebas unitarias aquí, más 16 de extremo a extremo";
    try std.testing.expectEqual(@as(?usize, 162), statedUnitTestTotal(spanish));

    // A missing figure is a failure for the caller to hear about, not a zero.
    try std.testing.expectEqual(@as(?usize, null), statedUnitTestTotal("nothing here"));
    try std.testing.expectEqual(@as(?usize, null), statedUnitTestTotal(" unit tests here"));
}

test "the test total is read out of a document, in either language and across a line wrap" {
    // The figure in the architecture documents is the one this repository has
    // let go stale four times, and the second time it went stale it did so in one
    // language only while the other was corrected. So the extraction is
    // exercised on both shapes here rather than on the document that happens to
    // be current.
    const english =
        "The root `test` step compiles and runs every suite: 248 tests across transcript" ++
        "\n(20), commitment (16)";
    try std.testing.expectEqual(@as(?usize, 248), statedTestTotal(english));

    // The same sentence with the figure pushed onto the next line by wrapping,
    // which is what the Spanish document does and what an English-only reader
    // would never notice.
    const spanish =
        "El paso `test` de la raíz compila y ejecuta todas las suites: 248 pruebas" ++
        "\nrepartidas en transcript (20)";
    try std.testing.expectEqual(@as(?usize, 248), statedTestTotal(spanish));

    // A document that stops stating a total is a failure for the caller to hear
    // about, not a figure of zero to be compared.
    try std.testing.expectEqual(@as(?usize, null), statedTestTotal("nothing to see here"));
    try std.testing.expectEqual(@as(?usize, null), statedTestTotal("runs every suite: "));
}

test "path comparisons survive a backslash separator" {
    // The Windows failure: paths there come back with backslashes, and comparing
    // them against a prefix written with a forward slash made this gate report a
    // repository with no sources in it, on three platforms, while passing here.
    // The assertion runs over the shape Windows produces, from a platform that
    // does not have the problem.
    try std.testing.expect(pathUnder("libs/stark/binius/stark.zig", "libs/"));
    try std.testing.expect(pathUnder("libs\\stark\\binius\\stark.zig", "libs/"));
    try std.testing.expect(pathUnder("libs\\stark\\binius\\stark.zig", "libs/stark/binius"));
    try std.testing.expect(pathUnder("libs/stark", "libs/stark"));
    try std.testing.expect(!pathUnder("libs/starkly/thing.zig", "libs/stark"));
    try std.testing.expect(!pathUnder("scripts/check_docs.zig", "libs/"));
    try std.testing.expect(!pathUnder("libs", "libs/"));
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

test "a gate that reads no manifest says so instead of reporting zeroes" {
    // The failure this guards is the one that reached CI: the gate ran from a
    // directory that was not the repository root, read no manifest, skipped them
    // all silently, and reported every zone at zero asserts. Here it reads
    // nothing, so the guard has to be the thing that speaks.
    const alloc = std.testing.allocator;

    var problems: std.ArrayList(Problem) = .empty;
    defer problems.deinit(alloc);

    var p: Problem = .{};
    p.setWhat("root", .{});
    p.setDetail("no build.zig.zon could be read from the working directory, so " ++
        "this gate is not looking at the repository. It would otherwise " ++
        "report every zone at zero and every module unused", .{});
    try problems.append(alloc, p);

    try std.testing.expectEqual(@as(usize, 1), problems.items.len);
    try std.testing.expectEqualStrings("root", problems.items[0].what[0..problems.items[0].what_len]);
    // The message has to name the failure and not merely the symptom, because
    // the symptom reads like a ledger that needs a ratchet.
    try std.testing.expect(std.mem.indexOf(u8, problems.items[0].detail[0..problems.items[0].detail_len], "not looking at the repository") != null);
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
    try std.testing.expectEqual(@as(usize, 60), declared_reachable);
    // transcript is the zone that proves reachability is a declared claim: both
    // of its asserts are `pub fn` inside something private.
    var fixture_zones: usize = 0;
    for (ledger) |zone| {
        if (zone.kind == .fixture) fixture_zones += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), fixture_zones);
}

test "the wiring rule reads module names out of a build file" {
    var sink: std.ArrayList([]const u8) = .empty;
    defer sink.deinit(std.testing.allocator);

    scanCodeForWiring(
        \\    signature_mod.addImport("zig-rng", traits_mod);\n\
    , &sink, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), sink.items.len);
    try std.testing.expectEqualStrings("zig-rng", sink.items[0]);

    var sink2: std.ArrayList([]const u8) = .empty;
    defer sink2.deinit(std.testing.allocator);
    scanCodeForWiring(
        \\    const m = dep.module("zig-curve");\n    x.addImport("zig-hash", m);\n\
    , &sink2, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), sink2.items.len);
}

test "the wiring rule ignores a module named in a comment" {
    var sink: std.ArrayList([]const u8) = .empty;
    defer sink.deinit(std.testing.allocator);
    // `zig-rng` sat wired into two libraries' builds and this rule could not see
    // it. A rule that also fired on comments would be noise on day one.
    scanCodeForWiring(
        \\    // signature_mod.addImport("zig-rng", traits_mod);\n\
    , &sink, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), sink.items.len);
}
