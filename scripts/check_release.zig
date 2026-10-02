//! Check that the version in `build.zig.zon` and the tag that publishes it
//! describe the same release.
//!
//! This gate exists because `AGENTS.md` used to state the rule as "the tag points
//! at the commit where the version was set". That is a convention a person applies
//! by remembering it, and on 0.7.1 it was remembered wrong: the version was set
//! three commits before the CI fix that made a fresh clone green, so tagging the
//! version commit would have published a release that fails on checkout. The rule
//! drifted because nobody decided to let it -- it just was not checkable.
//!
//! What it checks:
//!
//!   * The history is complete. `check-docs` reads history with `git show`, and
//!     against a checkout one commit deep every seal reads as pointing at a commit
//!     that does not exist. A gate that skips when it cannot see far enough is the
//!     silent degradation this repository keeps refusing, so this one fails
//!     instead -- the same reasoning as `check-docs` rule 8, and the reason the CI
//!     checkout asks for the full history.
//!   * The tag `v<version>` exists, where `<version>` is the manifest's own
//!     `.version`. "Nothing is tagged" is not the same as "what is tagged is
//!     right", so the absence is a failure and not a pass.
//!   * The tag is annotated and signed. A lightweight tag is a ref and nothing
//!     else, and an unsigned message is a note in a file that anybody can rewrite.
//!   * The manifest read out of the *tagged commit* declares that same version.
//!     The file in the working tree is still being edited and says nothing about
//!     what a tag published.
//!   * The tagged commit is reachable from `main`, or the tag publishes something
//!     a clone never receives.
//!
//! It is not a dependency of `zig build test`, and not because it needs anything
//! `test` cannot have. The tag does not exist until after CI is green, so a rule
//! about the tag cannot gate the commit that precedes it; wiring it in would leave
//! a permanent red build for the length of every release, which is the shape of a
//! gate people learn to ignore. CI runs it on tag pushes instead, which is the
//! moment the thing it describes comes into existence.

const std = @import("std");

const max_detail = 224;

const Problem = struct {
    what: []const u8 = "",
    detail: [max_detail]u8 = undefined,
    detail_len: usize = 0,

    fn set(self: *Problem, comptime fmt: []const u8, args: anytype) void {
        // A fixed buffer turns an over-long message into "detail too long", which
        // names the buffer instead of the failure -- and that is what came out of
        // `check-docs` while looking for a missing commit. Truncating to the first
        // sentence keeps the part that names what went wrong.
        const s = std.fmt.bufPrint(self.detail[0..], fmt, args) catch blk: {
            const corte = @min(std.mem.indexOfScalar(u8, fmt, '.') orelse max_detail, max_detail);
            @memcpy(self.detail[0..corte], fmt[0..corte]);
            break :blk self.detail[0..corte];
        };
        self.detail_len = s.len;
    }

    fn message(self: *const Problem) []const u8 {
        return self.detail[0..self.detail_len];
    }
};

fn gitAlloc(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8) ?[]const u8 {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return null;
    var buf: [8192]u8 = undefined;
    var reader = child.stdout.?.readerStreaming(io, &buf);
    const out = reader.interface.allocRemaining(alloc, .limited(1 << 20)) catch return null;
    // The exit code is the whole answer here. `git rev-parse --verify --quiet` on a
    // tag that does not exist prints nothing and fails, so a reader that only read
    // stdout would hand back an empty string and every rule below would compare
    // empty strings and pass.
    switch (child.wait(io) catch return null) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    return std.mem.trim(u8, out, " \t\r\n");
}

fn isHexSha(text: []const u8) bool {
    if (text.len != 40) return false;
    for (text) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

/// The `.version` value in a manifest, verbatim.
fn manifestVersion(text: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, t, ".version")) continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        // Trimmed of a trailing comma as well as of space: the line in a zon file
        // reads `.version = "0.7.1",` and a parser that expects the closing quote
        // to be the last byte returns nothing at all -- which is a gate that finds
        // no version and so cannot tell "no version" from "no parser".
        const value = std.mem.trim(u8, t[eq + 1 ..], " \t,");
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') continue;
        return value[1 .. value.len - 1];
    }
    return null;
}

fn report(problems: *std.ArrayList(Problem)) u8 {
    if (problems.items.len == 0) {
        std.debug.print("release check passed\n", .{});
        return 0;
    }
    std.debug.print("release check failed:\n", .{});
    for (problems.items) |*p| {
        std.debug.print("  - {s}: {s}\n", .{ p.what, p.message() });
    }
    return 1;
}

pub fn main(init: std.process.Init) !u8 {
    var arena_state: std.heap.ArenaAllocator = .init(init.arena.allocator());
    defer arena_state.deinit();
    const alloc = arena_state.allocator();
    const io = init.io;

    var problems: std.ArrayList(Problem) = .empty;
    defer problems.deinit(alloc);

    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer cwd.close(io);

    const manifest = cwd.readFileAlloc(io, "build.zig.zon", alloc, .limited(1 << 20)) catch |err| {
        var p: Problem = .{ .what = "build.zig.zon" };
        p.set("cannot be read: {s}", .{@errorName(err)});
        return report(&problems);
    };
    const version = manifestVersion(manifest) orelse {
        var p: Problem = .{ .what = "build.zig.zon" };
        p.set("has no .version, so there is no version for a tag to publish", .{});
        try problems.append(alloc, p);
        return report(&problems);
    };

    // Rule 0, and the reason it is stated separately: a checkout one commit deep
    // cannot answer any of the questions below, and the answer it gives is "no" to
    // all of them, which is indistinguishable from a repository where nothing was
    // ever tagged.
    if (gitAlloc(alloc, io, &.{ "git", "rev-parse", "--is-shallow-repository" })) |flag| {
        if (std.mem.indexOf(u8, flag, "true") != null) {
            var p: Problem = .{ .what = "history" };
            p.set("this checkout is shallow, so no rule below can be checked. " ++
                "This gate fails rather than skips: a control that quietly stops " ++
                "running is worse than one that is absent, because the second is " ++
                "visible", .{});
            try problems.append(alloc, p);
            return report(&problems);
        }
    }

    const tag = try std.fmt.allocPrint(alloc, "v{s}", .{version});

    const tagged = gitAlloc(alloc, io, &.{ "git", "rev-parse", "--verify", "--quiet", tag });
    if (tagged == null) {
        var p: Problem = .{ .what = tag };
        p.set("does not exist, and the manifest declares {s}. The release that " ++
            "publishes it is untagged", .{version});
        try problems.append(alloc, p);
        return report(&problems);
    }

    // Annotated and signed. `cat-file -t` tells a tag object from a commit, which
    // is how the two are told apart without a heuristic.
    const kind = gitAlloc(alloc, io, &.{ "git", "cat-file", "-t", tag }) orelse "unknown";
    if (!std.mem.eql(u8, kind, "tag")) {
        var p: Problem = .{ .what = tag };
        p.set("is a {s} rather than an annotated tag. A lightweight tag is a ref " ++
            "and carries no message and no signature", .{kind});
        try problems.append(alloc, p);
    } else {
        const body = gitAlloc(alloc, io, &.{ "git", "cat-file", "-p", tag }) orelse "";
        if (std.mem.indexOf(u8, body, "-----BEGIN PGP SIGNATURE-----") == null) {
            var p: Problem = .{ .what = tag };
            p.set("is annotated but not signed. The message is the statement a " ++
                "reader keeps, and an unsigned one is a note in a file that " ++
                "anybody can rewrite", .{});
            try problems.append(alloc, p);
        }
    }

    // The manifest inside the tagged commit, not the one in the working tree. This
    // is the check the old rule was reaching for by hand: a version number in a
    // file that is still being edited says nothing about what a tag published.
    const spec = try std.fmt.allocPrint(alloc, "{s}^{{}}", .{tag});
    const tagged_manifest = gitAlloc(alloc, io, &.{ "git", "show", spec, ":build.zig.zon" });
    if (tagged_manifest == null) {
        var p: Problem = .{ .what = tag };
        p.set("does not resolve to a commit carrying a build.zig.zon", .{});
        try problems.append(alloc, p);
    } else if (manifestVersion(tagged_manifest.?)) |published| {
        if (!std.mem.eql(u8, published, version)) {
            var p: Problem = .{ .what = tag };
            p.set("publishes version {s} and the manifest says {s}. The tag and the " ++
                "manifest have to describe the same release", .{ published, version });
            try problems.append(alloc, p);
        }
    } else {
        var p: Problem = .{ .what = tag };
        p.set("commits a build.zig.zon with no .version", .{});
        try problems.append(alloc, p);
    }

    if (isHexSha(tagged.?)) {
        if (gitAlloc(alloc, io, &.{ "git", "merge-base", "--is-ancestor", tagged.?, "main" }) == null) {
            var p: Problem = .{ .what = tag };
            p.set("points at a commit that is not on main. A tag publishes a " ++
                "release, and a release nobody receives by cloning is not one", .{});
            try problems.append(alloc, p);
        }
    }

    return report(&problems);
}
