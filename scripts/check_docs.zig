//! Checks that the markdown documentation is bilingual and monolingual.
//!
//! Rules:
//!   1. Every markdown file has a counterpart in the other language: the bare
//!      name is English, `<name>.es.md` is Spanish.
//!   2. Every file declares its language and links to its pair in its first
//!      three lines.
//!   3. The prose of a file does not contain stopwords from the other language.
//!
//! Fenced code blocks and inline code are stripped before rule 3, because
//! identifiers are the same in both languages. A file without a counterpart is a
//! failure, not a skip: a new document has to arrive in both languages.

const std = @import("std");

const english_stop = [_][]const u8{
    "the",   "and",   "with",   "this",  "that", "must", "should",
    "which", "there", "where",  "from",  "not",  "are",  "were",
    "each",  "will",  "cannot", "into",  "have", "have", "been",
    "their", "would", "could",  "about",
};

// Single letters are excluded on purpose: short tokens produce false positives
// ("m" is a Spanish conjunction and also a unit, "la" appears inside paths).
const spanish_stop = [_][]const u8{
    "el",    "la",    "los",   "las",    "una",     "uno",   "para",
    "con",   "como",  "pero",  "tambi",  "debe",    "este",  "esta",
    "esto",  "desde", "cada",  "donde",  "puede",   "deben", "entre",
    "sobre", "solo",  "hacia", "ningun", "tambien", "estas", "este",
};

// Anglicisms that have a clean Spanish equivalent. Deliberately excluded:
// identifiers (`std.debug.print`, `zig build test`), Zig build vocabulary
// (build, Debug, ReleaseFast), and Git vocabulary (commit, tag, rebase, merge),
// which are used as proper names in this project's own toolchain. `hash` is also
// excluded: it appears inside dependency names such as `zig-hash`.
const anglicisms = [_][]const u8{
    "backend", "layout", "assert",  "asserts", "print",  "bug",
    "setup",   "output", "test",    "tests",   "lookup", "lookups",
    "deploy",  "staff",  "folders", "prints",
};

const max_detail = 224;
/// Every file under `root`, recursively, as paths relative to it and always
/// separated by `/`.
///
/// This replaces `Dir.walk`, which returned almost nothing on Windows and took
/// the documentation gate with it: it reported "2 files, all paired" while the
/// repository has 22 documents. Owning the recursion means the path separator
/// the platform uses never reaches a comparison, and the directories that are a
/// package cache or a version-control directory are never entered.
fn collectFiles(
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
        const child = if (prefix.len == 0)
            try alloc.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(alloc, "{s}/{s}", .{ prefix, entry.name });
        switch (entry.kind) {
            .directory => {
                if (std.mem.eql(u8, entry.name, "zig-pkg")) continue;
                if (std.mem.eql(u8, entry.name, ".zig-cache")) continue;
                if (std.mem.eql(u8, entry.name, ".git")) continue;
                if (std.mem.eql(u8, entry.name, ".opencode")) continue;
                try collectFiles(alloc, io, cwd, child, out);
            },
            else => try out.append(alloc, child),
        }
    }
}

const Problem = struct {
    path: [512]u8 = undefined,
    path_len: usize = 0,
    detail: [max_detail]u8 = undefined,
    detail_len: usize = 0,

    fn setPath(self: *Problem, p: []const u8) void {
        const n = @min(p.len, self.path.len);
        @memcpy(self.path[0..n], p[0..n]);
        self.path_len = n;
    }

    fn setDetail(self: *Problem, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(self.detail[0..], fmt, args) catch blk: {
            const s = "detail too long";
            @memcpy(self.detail[0..s.len], s);
            break :blk s;
        };
        self.detail_len = s.len;
    }

    fn pathSlice(self: *const Problem) []const u8 {
        return self.path[0..self.path_len];
    }

    fn detailSlice(self: *const Problem) []const u8 {
        return self.detail[0..self.detail_len];
    }
};

/// Digits count as word characters, so "M31" is one word and does not match a
/// stopword inside it.
fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c >= 0x80;
}

/// Copy the prose of `text` into `out`, dropping fenced code blocks and inline
/// code spans.
///
/// Line based, because that is how markdown works: a fence is a line whose
/// first non-space characters are three backticks. A byte scanner gets this
/// wrong, because a three-backtick fence looks like a fence plus the start of an
/// inline span, which then swallows the rest of the document.
fn stripCode(alloc: std.mem.Allocator, text: []const u8, out: *std.ArrayList(u8)) !bool {
    var in_fence = false;
    // A line indented by four or more spaces is a markdown code block only when
    // it follows a blank line (or another line of the same block).
    var prev_blank = true;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const trimmed = std.mem.trimStart(u8, raw, " \t");
        if (std.mem.startsWith(u8, trimmed, "```")) {
            in_fence = !in_fence;
            prev_blank = false;
            continue;
        }
        if (in_fence) {
            prev_blank = false;
            continue;
        }
        const indent = raw.len - trimmed.len;
        if (indent >= 4 and prev_blank) {
            prev_blank = false;
            continue;
        }
        prev_blank = std.mem.trim(u8, raw, " \t").len == 0;

        // Drop inline `code` spans, keeping the rest of the line.
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '`') {
                const rest = std.mem.indexOfScalar(u8, raw[i + 1 ..], '`') orelse {
                    i += 1;
                    continue;
                };
                i = i + 1 + rest + 1;
                continue;
            }
            try out.append(alloc, raw[i]);
            i += 1;
        }
        try out.append(alloc, '\n');
    }
    return !in_fence;
}

fn containsWord(text: []const u8, word: []const u8) bool {
    if (word.len == 0) return false;
    var i: usize = 0;
    while (i + word.len <= text.len) : (i += 1) {
        if (!std.ascii.eqlIgnoreCase(text[i .. i + word.len], word)) continue;
        const before_ok = i == 0 or !isWordByte(text[i - 1]);
        const after = i + word.len;
        const after_ok = after >= text.len or !isWordByte(text[after]);
        if (before_ok and after_ok) return true;
    }
    return false;
}

/// Returns the link target of the language banner, or null when there is none.
/// The banner must be a blockquote naming the language and pointing at the pair.
fn bannerLink(text: []const u8) ?[]const u8 {
    var lines: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        lines += 1;
        if (lines > 3) break;
        if (line.len < 2 or line[0] != '>') continue;
        const mentions_language = std.mem.indexOf(u8, line, "English") != null or
            std.mem.indexOf(u8, line, "Espa") != null;
        if (!mentions_language) continue;
        const open = std.mem.indexOf(u8, line, "](") orelse return null;
        const start = open + 2;
        const rest = line[start..];
        const off = std.mem.indexOfScalar(u8, rest, ')') orelse return null;
        const end = start + off;
        return line[start..end];
    }
    return null;
}

fn counterpartName(alloc: std.mem.Allocator, name: []const u8) !?[]const u8 {
    if (std.mem.endsWith(u8, name, ".es.md")) {
        return try std.fmt.allocPrint(alloc, "{s}.md", .{name[0 .. name.len - ".es.md".len]});
    }
    if (std.mem.endsWith(u8, name, ".md")) {
        return try std.fmt.allocPrint(alloc, "{s}.es.md", .{name[0 .. name.len - ".md".len]});
    }
    return null;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.arena.allocator();
    const io = init.io;
    // Dir.cwd() is not opened with iteration capability, so open it first.
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer cwd.close(io);

    var problems: std.ArrayList(Problem) = .empty;
    defer problems.deinit(alloc);
    var checked: usize = 0;

    var all: std.ArrayList([]const u8) = .empty;
    defer {
        for (all.items) |p| alloc.free(p);
        all.deinit(alloc);
    }
    try collectFiles(alloc, io, cwd, "", &all);

    for (all.items) |path| {
        if (!std.mem.endsWith(u8, path, ".md")) continue;

        const base = std.fs.path.basename(path);

        var problem: Problem = .{};
        problem.setPath(path);

        const pair_name = (try counterpartName(alloc, base)) orelse {
            problem.setDetail("file name is neither <name>.md nor <name>.es.md", .{});
            try problems.append(alloc, problem);
            continue;
        };
        defer alloc.free(pair_name);

        const dir_path = std.fs.path.dirname(path) orelse ".";
        const pair_path = try std.fs.path.join(alloc, &.{ dir_path, pair_name });
        defer alloc.free(pair_path);

        cwd.access(io, pair_path, .{}) catch {
            problem.setDetail("missing counterpart {s}", .{pair_path});
            try problems.append(alloc, problem);
            continue;
        };

        const text = cwd.readFileAlloc(io, path, alloc, .limited(1 << 20)) catch |err| {
            problem.setDetail("cannot read: {s}", .{@errorName(err)});
            try problems.append(alloc, problem);
            continue;
        };
        defer alloc.free(text);
        checked += 1;

        const link = bannerLink(text);
        if (link == null) {
            problem.setDetail("no language banner linking to the pair at the top", .{});
            try problems.append(alloc, problem);
        } else if (!std.mem.eql(u8, link.?, std.fs.path.basename(pair_path))) {
            problem.setDetail("banner points at {s}, not at {s}", .{
                link.?, std.fs.path.basename(pair_path),
            });
            try problems.append(alloc, problem);
        }

        var prose: std.ArrayList(u8) = .empty;
        defer prose.deinit(alloc);
        if (!try stripCode(alloc, text, &prose)) {
            problem.setDetail("unbalanced code fence: everything after it went unchecked", .{});
            try problems.append(alloc, problem);
        }

        const is_es = std.mem.endsWith(u8, base, ".es.md");
        const foreign = if (is_es) english_stop[0..] else spanish_stop[0..];

        // Reportable words: stopwords of the other language, plus, for Spanish
        // files, the anglicisms that have a clean Spanish equivalent.
        var reportable: std.ArrayList([]const u8) = .empty;
        defer reportable.deinit(alloc);
        try reportable.appendSlice(alloc, foreign);
        if (is_es) try reportable.appendSlice(alloc, anglicisms[0..]);

        if (reportable.items.len > 0) {
            var detail: [max_detail]u8 = undefined;
            var len: usize = 0;
            const prefix = if (is_es)
                "English words or anglicisms: "
            else
                "palabras en espa\u{00f1}ol: ";
            @memcpy(detail[0..prefix.len], prefix);
            len = prefix.len;
            var shown: usize = 0;
            for (reportable.items) |w| {
                if (shown == 8) break;
                if (!containsWord(prose.items, w)) continue;
                if (shown > 0) {
                    if (len + 2 > detail.len) break;
                    detail[len] = ',';
                    detail[len + 1] = ' ';
                    len += 2;
                }
                const n = @min(w.len, detail.len - len);
                @memcpy(detail[len .. len + n], w[0..n]);
                len += n;
                shown += 1;
            }
            if (shown > 0) {
                problem.setDetail("{s}", .{detail[0..len]});
                try problems.append(alloc, problem);
            }
        }
    }

    if (problems.items.len > 0) {
        std.debug.print("documentation check failed:\n", .{});
        for (problems.items) |*p| {
            std.debug.print("  - {s}: {s}\n", .{ p.pathSlice(), p.detailSlice() });
        }
        return 1;
    }

    // A gate that verified a handful of files is not a gate that passed, it is a
    // gate that looked at the wrong directory. This one reported "2 files, all
    // paired" in CI while the repository has 22 documents, because the working
    // directory was not the repository root and the walk found whatever markdown
    // happened to be below it. The root has markers; require them.
    inline for (.{ "README.md", "build.zig.zon", "AGENTS.md", "CHANGELOG.md" }) |marker| {
        std.Io.Dir.cwd().access(io, marker, .{}) catch {
            std.debug.print(
                "documentation check failed: {s} is not in the working directory, so this " ++
                    "gate is not looking at the repository root. It saw {d} files, which " ++
                    "is not a verification of anything\n",
                .{ marker, checked },
            );
            return error.NotRepositoryRoot;
        };
    }
    std.debug.print("documentation check passed: {d} files, all paired, no language mixing\n", .{checked});
    return 0;
}
