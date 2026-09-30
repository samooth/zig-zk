//! Rewrite `scripts/algebra-tags.txt` from the tags `zig-algebra` has published.
//!
//! This is the only step in the tree that writes the reference, and it is the
//! only one that needs the network. It runs when a person runs it, which is why
//! `scripts/check_pins_fresh.zig` exists: if this is the only half of the
//! mechanism, correctness depends on somebody remembering, and that is a protocol
//! rather than a gate.
//!
//! Two things it refuses to do. It does not leave a half-written file behind --
//! the body is built in memory and written in one call, because a file that exists
//! and is wrong is worse than one that is absent, and an assert that cuts halfway
//! leaves a tree that looks fine and is not. And it does not invent a version if
//! the remote cannot be read: no output at all, and a non-zero exit.
//!
//! The listing it writes is the input to the pin rule in `check_contract.zig`,
//! which reads the file and never the network.

const std = @import("std");

/// Where the tags are fetched from. It is the same url the manifests pin, read
/// from the same place, so there is one source for both and a third copy cannot
/// drift from them.
const manifest_path = "build.zig.zon";
const manifest_dep = "zig_algebra";
const tags_path = "scripts/algebra-tags.txt";

/// The header the file carries, so the two commands that own it are named inside
/// it. A file that documents itself cannot drift from the commands that maintain
/// it, because anyone editing it is reading the commands.
const header =
    \\# Published tags of zig-algebra, oldest first.
    \\
    \\# This file is the reference the pin gate compares against. It is committed on
    \\# purpose: a gate that reads the network gives a different answer in CI than it
    \\# does on a laptop, and a gate that sometimes knows is not a gate.
    \\
    \\# Two commands own it, and the split matters:
    \\
    \\#   zig build refresh-algebra-tags   writes this file, from `git ls-remote` on the
    \\#                                   url in build.zig.zon. This is the only step
    \\#                                   that needs the network, and it is a person
    \\#                                   running it.
    \\
    \\#   zig build check-pins-fresh      compares this file against that same
    \\#                                   `git ls-remote` and fails if they differ.
    \\#                                   Also needs the network, also not a dependency
    \\#                                   of `zig build test` -- it is the gate for the
    \\#                                   reference, and a reference that cannot go
    \\#                                   stale unnoticed is not a reference.
    \\
    \\# `zig build test` reads this file and nothing else. It is the freshness check that
    \\# fails when a tag is cut upstream and nobody runs the refresh.
    \\
    \\# The gap between v0.3.2 and v0.5.1 is real: zig-algebra published no v0.4.x and no
    \\# v0.5.0. So "one release behind" is a position in this list and not a subtraction
    \\# of version numbers, because 0.6.0 - 0.5.3 is seven releases by minor and patch
    \\# arithmetic and one by publication.
    \\
;

/// Pull the `zig_algebra` dependency url out of the root manifest. Read rather
/// than repeated: a hardcoded url here would be a third copy of the pin, and the
/// bug this whole mechanism exists for was a copy that nobody was watching.
fn algebraUrl(alloc: std.mem.Allocator, text: []const u8) ![]const u8 {
    const anchor = ".zig_algebra = .{";
    const at = std.mem.indexOf(u8, text, anchor) orelse return error.NoAlgebraDependency;
    const open = at + anchor.len;
    const url_at = std.mem.indexOfPos(u8, text, open, ".url = \"") orelse return error.NoAlgebraUrl;
    const start = url_at + ".url = \"".len;
    const end = std.mem.indexOfPos(u8, text, start, "\"") orelse return error.UnterminatedUrl;
    const url = try alloc.dupe(u8, text[start..end]);
    // The manifest points at an archive tarball; the tags live at the repository
    // behind it, which is the same url without the `/archive/...` suffix.
    const cut = std.mem.indexOf(u8, url, "/archive/") orelse return error.NotAnArchiveUrl;
    return try alloc.dupe(u8, url[0..cut]);
}

fn compareLessThan(_: void, a: []const u8, b: []const u8) bool {
    return lessThanVersion(a, b);
}

/// Semantic ordering over `vX.Y.Z`, by hand rather than with a library: the only
/// shapes that reach this file are the ones `git ls-remote` returns for a
/// semver-tagged repository, and a dependency on a version parser for eleven
/// lines of comparison is not a trade worth making. It splits on the same
/// separators `check_contract.zig` parses the pin with, so the two agree.
fn lessThanVersion(a: []const u8, b: []const u8) bool {
    var ai: usize = if (a.len > 0 and a[0] == 'v') 1 else 0;
    var bi: usize = if (b.len > 0 and b[0] == 'v') 1 else 0;
    var part: u8 = 0;
    while (part < 3) : (part += 1) {
        var av: u32 = 0;
        var bv: u32 = 0;
        while (ai < a.len and std.ascii.isDigit(a[ai])) : (ai += 1) {
            av = av * 10 + (a[ai] - '0');
        }
        while (bi < b.len and std.ascii.isDigit(b[bi])) : (bi += 1) {
            bv = bv * 10 + (b[bi] - '0');
        }
        if (av != bv) return av < bv;
        if (ai < a.len and a[ai] == '.') ai += 1;
        if (bi < b.len and b[bi] == '.') bi += 1;
    }
    return false;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.arena.allocator();
    const io = init.io;

    // Everything that can fail happens before a single byte is written. After the
    // first successful read, the only remaining failure is the write itself.
    const manifest = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, alloc, .limited(1 << 20)) catch |err| {
        std.debug.print("cannot read {s}: {s}\n", .{ manifest_path, @errorName(err) });
        return 1;
    };
    const url = algebraUrl(alloc, manifest) catch |err| {
        std.debug.print("cannot read the {s} url out of {s}: {s}\n", .{ manifest_dep, manifest_path, @errorName(err) });
        return 1;
    };

    var child = std.process.spawn(io, .{
        .argv = &.{ "git", "ls-remote", "--tags", "--refs", url },
        .stdout = .pipe,
        .stderr = .inherit,
    }) catch |err| {
        std.debug.print("cannot run git for {s}: {s}\n", .{ url, @errorName(err) });
        return 1;
    };
    var pipe_buf: [4096]u8 = undefined;
    var pipe_reader = child.stdout.?.readerStreaming(io, &pipe_buf);
    const stdout = pipe_reader.interface.allocRemaining(alloc, .limited(1 << 22)) catch |err| {
        std.debug.print("cannot read git's output: {s}\n", .{@errorName(err)});
        return 1;
    };
    switch (child.wait(io) catch |err| {
        std.debug.print("git ls-remote failed for {s}: {s}\n", .{ url, @errorName(err) });
        return 1;
    }) {
        .exited => |code| if (code != 0) {
            std.debug.print("git ls-remote exited {d} for {s}\n", .{ code, url });
            return 1;
        },
        else => {},
    }

    var tags: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        const marker = "refs/tags/";
        const at = std.mem.lastIndexOf(u8, t, marker) orelse continue;
        const tag = t[at + marker.len ..];
        // `--refs` already drops the dereferenced `^{}` lines, but a tag that is
        // not a version is not part of the pin's history and does not belong in a
        // listing the pin gate walks.
        if (tag.len < 3 or tag[0] != 'v' or !std.ascii.isDigit(tag[1])) continue;
        // Annotated tags appear twice with `--tags`; `--refs` removes the second.
        for (tags.items) |seen| {
            if (std.mem.eql(u8, seen, tag)) break;
        } else try tags.append(alloc, tag);
    }

    if (tags.items.len == 0) {
        std.debug.print("no version tags under refs/tags at {s}, so there is nothing to write.\n", .{url});
        std.debug.print("The existing file is left untouched: an empty listing would make the pin gate pass always.\n", .{});
        return 1;
    }

    std.mem.sort([]const u8, tags.items, {}, compareLessThan);

    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(alloc, header);
    for (tags.items) |tag| {
        try body.appendSlice(alloc, tag);
        try body.append(alloc, '\n');
    }

    // One write, and it is the last thing that can fail. A file that exists and
    // is half written is worse than one that is absent, because the gate reads it
    // and concludes the listing is merely old.
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = tags_path,
        .data = body.items,
    }) catch |err| {
        std.debug.print("cannot write {s}: {s}\n", .{ tags_path, @errorName(err) });
        return 1;
    };

    std.debug.print("{s}: {d} tags, newest {s}\n", .{
        tags_path,
        tags.items.len,
        tags.items[tags.items.len - 1],
    });
    return 0;
}

test "the algebra url is read out of the manifest, not repeated" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const manifest =
        \\.dependencies = .{
        \\    .zig_algebra = .{
        \\        .url = "https://github.com/samooth/zig-algebra/archive/refs/tags/v0.6.0.tar.gz",
        \\        .hash = "zig_algebra-0.6.0-x",
        \\    },
        \\},
    ;
    try std.testing.expectEqualStrings(
        "https://github.com/samooth/zig-algebra",
        try algebraUrl(alloc, manifest),
    );
}

test "a manifest with no algebra url fails instead of guessing" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    try std.testing.expectError(error.NoAlgebraDependency, algebraUrl(alloc, ".dependencies = .{}"));
    try std.testing.expectError(error.NoAlgebraUrl, algebraUrl(alloc, ".zig_algebra = .{ .hash = \"x\" },"));
}

test "version ordering is by component, not by string" {
    try std.testing.expect(lessThanVersion("v0.3.2", "v0.5.1"));
    try std.testing.expect(lessThanVersion("v0.5.9", "v0.6.0"));
    try std.testing.expect(lessThanVersion("0.5.3", "0.6.0"));
    try std.testing.expect(!lessThanVersion("v0.6.0", "v0.6.0"));
    try std.testing.expect(!lessThanVersion("v0.6.0", "v0.5.3"));
    // The gap that makes this matter: algebra published no v0.4.x, so a listing
    // that skipped it and compared 0.5.3 to 0.6.0 numerically would call them seven
    // releases apart.
    try std.testing.expect(lessThanVersion("v0.3.2", "v0.5.1"));
}
