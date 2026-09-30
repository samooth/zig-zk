//! Fail if `scripts/algebra-tags.txt` differs from the tags `zig-algebra` has
//! actually published.
//!
//! This is the gate for the reference. `check_contract.zig` compares the pin
//! against the committed listing and never touches the network, which is what
//! makes `zig build test` hermetic -- and it is exactly why the listing can go
//! stale. A tag gets cut upstream, nobody runs `refresh-algebra-tags`, and the
//! pin rule keeps comparing against last month's list and keeps passing. That is
//! the shape of the failure this whole mechanism exists to catch, reproduced one
//! level down, and it is why this step exists rather than only the refresh.
//!
//! It is not a dependency of `zig build test`, on purpose. It needs the network,
//! so it belongs where a network exists, and a hermetic gate that silently
//! depended on one would give a different answer offline than in CI.
//!
//! It reports a difference rather than fixing it. A gate that rewrites the file it
//! is checking is not checking it, and the refresh is a decision -- it says what
//! this repository believes upstream has released, and that is a person's call.

const std = @import("std");

const manifest_path = "build.zig.zon";
const manifest_dep = "zig_algebra";
const tags_path = "scripts/algebra-tags.txt";

fn algebraUrl(alloc: std.mem.Allocator, text: []const u8) ![]const u8 {
    const anchor = ".zig_algebra = .{";
    const at = std.mem.indexOf(u8, text, anchor) orelse return error.NoAlgebraDependency;
    const url_at = std.mem.indexOfPos(u8, text, at + anchor.len, ".url = \"") orelse return error.NoAlgebraUrl;
    const start = url_at + ".url = \"".len;
    const end = std.mem.indexOfPos(u8, text, start, "\"") orelse return error.UnterminatedUrl;
    const url = try alloc.dupe(u8, text[start..end]);
    const cut = std.mem.indexOf(u8, url, "/archive/") orelse return error.NotAnArchiveUrl;
    return try alloc.dupe(u8, url[0..cut]);
}

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

fn compareLessThan(_: void, a: []const u8, b: []const u8) bool {
    return lessThanVersion(a, b);
}

/// The version tags in `git ls-remote --tags --refs` output.
fn tagsIn(alloc: std.mem.Allocator, stdout: []const u8) !std.ArrayList([]const u8) {
    var tags: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        const marker = "refs/tags/";
        const at = std.mem.lastIndexOf(u8, t, marker) orelse continue;
        const tag = t[at + marker.len ..];
        if (tag.len < 3 or tag[0] != 'v' or !std.ascii.isDigit(tag[1])) continue;
        // Both sides of the comparison drop the leading v, so a mismatch means a
        // tag really is missing rather than the two sides spelling it differently.
        // Compared stripped, because that is what is stored: comparing the
        // stored form against the raw tag would never match and the duplicate
        // would survive, which is a listing with v0.6.0 in it twice.
        for (tags.items) |seen| {
            if (std.mem.eql(u8, seen, tag[1..])) break;
        } else try tags.append(alloc, tag[1..]);
    }
    std.mem.sort([]const u8, tags.items, {}, compareLessThan);
    return tags;
}

/// The version tags in a committed listing, in its own order, without comments.
fn listedIn(alloc: std.mem.Allocator, listing: []const u8) !std.ArrayList([]const u8) {
    var tags: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        const v = if (t[0] == 'v') t[1..] else t;
        try tags.append(alloc, v);
    }
    return tags;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.arena.allocator();
    const io = init.io;

    const cwd = std.Io.Dir.cwd();
    const manifest = cwd.readFileAlloc(io, manifest_path, alloc, .limited(1 << 20)) catch |err| {
        std.debug.print("cannot read {s}: {s}\n", .{ manifest_path, @errorName(err) });
        return 1;
    };
    const listing = cwd.readFileAlloc(io, tags_path, alloc, .limited(1 << 22)) catch |err| {
        std.debug.print("cannot read {s}: {s}\n", .{ tags_path, @errorName(err) });
        std.debug.print("Run `zig build refresh-algebra-tags` to create it.\n", .{});
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
        std.debug.print("This gate needs the network, which is why it is not part of `zig build test`.\n", .{});
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

    const published = try tagsIn(alloc, stdout);
    const listed = try listedIn(alloc, listing);

    if (published.items.len == 0) {
        std.debug.print("no version tags at {s}, so the listing cannot be checked.\n", .{url});
        std.debug.print("Treating that as a pass would make this gate pass whenever the network is unavailable.\n", .{});
        return 1;
    }

    // Report both directions. A tag upstream that is missing here is the failure
    // that matters -- it is the one that lets a stale pin through. A tag here that
    // upstream no longer has is the other direction and still worth saying, since
    // it means the listing has drifted rather than merely aged.
    var missing: std.ArrayList([]const u8) = .empty;
    for (published.items) |tag| {
        for (listed.items) |have| {
            if (std.mem.eql(u8, tag, have)) break;
        } else try missing.append(alloc, tag);
    }
    var extra: std.ArrayList([]const u8) = .empty;
    for (listed.items) |have| {
        for (published.items) |tag| {
            if (std.mem.eql(u8, tag, have)) break;
        } else try extra.append(alloc, have);
    }

    if (missing.items.len == 0 and extra.items.len == 0) {
        std.debug.print("{s} is current: {d} tags, newest {s}\n", .{
            tags_path, listed.items.len, listed.items[listed.items.len - 1],
        });
        return 0;
    }

    std.debug.print("{s} is out of date.\n", .{tags_path});
    for (missing.items) |tag| std.debug.print("  published upstream, missing here: {s}\n", .{tag});
    for (extra.items) |tag| std.debug.print("  listed here, not published:      {s}\n", .{tag});
    std.debug.print("Run `zig build refresh-algebra-tags` and commit the result.\n", .{});
    std.debug.print("Until then the pin gate is comparing against a list that is missing what upstream has released, which is how a pin stays a release behind without anything failing.\n", .{});
    return 1;
}

test "published tags are read in order and duplicates dropped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const out =
        "aaaa\trefs/tags/v0.6.0\n" ++
        "bbbb\trefs/tags/v0.3.2\n" ++
        "cccc\trefs/tags/v0.6.0\n" ++
        "dddd\trefs/tags/v0.5.3\n" ++
        "eeee\trefs/tags/nightly\n";
    const tags = try tagsIn(alloc, out);
    try std.testing.expectEqual(@as(usize, 3), tags.items.len);
    try std.testing.expectEqualStrings("0.3.2", tags.items[0]);
    try std.testing.expectEqualStrings("0.5.3", tags.items[1]);
    try std.testing.expectEqualStrings("0.6.0", tags.items[2]);
}

test "a listing's comments are not tags" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const listing =
        \\# Published tags of zig-algebra, oldest first.
        \\# v0.9.9 is mentioned here and is not a release.
        \\
        \\v0.5.3
        \\v0.6.0
        \\
    ;
    const tags = try listedIn(alloc, listing);
    try std.testing.expectEqual(@as(usize, 2), tags.items.len);
    try std.testing.expectEqualStrings("0.5.3", tags.items[0]);
    try std.testing.expectEqualStrings("0.6.0", tags.items[1]);
}

test "the url comes from the manifest rather than a third copy" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    try std.testing.expectEqualStrings("https://github.com/samooth/zig-algebra", try algebraUrl(alloc,
        \\.zig_algebra = .{
        \\    .url = "https://github.com/samooth/zig-algebra/archive/refs/tags/v0.6.0.tar.gz",
        \\},
    ));
}
