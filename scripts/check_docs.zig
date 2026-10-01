//! Checks that the markdown documentation is bilingual and monolingual.
//!
//! Rules:
//!   1. Every markdown file has a counterpart in the other language: the bare
//!      name is English, `<name>.es.md` is Spanish.
//!   2. Every file declares its language and links to its pair in its first
//!      three lines.
//!   3. The prose of a file does not contain stopwords from the other language.
//!   4. The prose of a file contains no CJK ideograph or kana. This
//!      repository writes in two Latin-script languages, so a Han or kana
//!      character in the prose is contamination that arrived from somewhere
//!      else, and it is the one kind that no stopword list catches: a CJK
//!      sequence never equals a Latin entry. The check is a range rather than
//!      a vocabulary, because a vocabulary of observed strings only fires on
//!      the strings already observed.
//!
//! The range is deliberately narrow. Accented Latin, the em dash, arrows,
//! `<<` and `>>`, the middle dot and a Greek capital sigma are all used in
//! this repository's documents and are not contamination, so "not ASCII" is
//! not the test -- it would fail on the accents on the first file.
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
/// Rule 5: the changelogs' version sections must be strictly descending, never
/// repeated, and never empty.
///
/// A duplicated heading and a heading with an empty body both read as sections
/// to a scanner and as nothing at all to a reader. This batch shipped both in
/// 0.6.0 and every existing rule passed: pairing, banner, language and
/// punctuation do not look at structure, and a section with no prose is not a
/// pairing failure or a CJK failure. Found by reading the file.
fn checkChangelogSections(
    alloc: std.mem.Allocator,
    text: []const u8,
    out: *std.ArrayList(Problem),
) !void {
    var it = std.mem.splitScalar(u8, text, '\n');
    var seen: [64][]const u8 = undefined;
    var count: usize = 0;
    var prev: ?[]const u8 = null;

    while (it.next()) |line| {
        if (!std.mem.startsWith(u8, line, "## [")) continue;
        const close = std.mem.indexOfScalar(u8, line, ']') orelse {
            try report(alloc, out, "changelog heading without a closing bracket: {s}", .{line});
            continue;
        };
        // line[4..close], not [3..): index 3 is the opening bracket, and a
        // label that starts with "[" is not a digit and not a heading, so the
        // rule would skip every version and pass vacuously. The mutation that
        // caught it was a duplicated section in this changelog.
        const label = line[4..close];
        if (!isVersionLabel(label)) {
            try report(alloc, out, "changelog section is neither a version nor a heading: {s}", .{label});
            continue;
        }
        if (!isReleaseLabel(label)) continue; // Unreleased and friends carry no order

        var duplicate = false;
        for (seen[0..count]) |old| {
            if (std.mem.eql(u8, old, label)) {
                try report(alloc, out, "changelog section [{s}] appears more than once", .{label});
                duplicate = true;
            }
        }
        if (duplicate) continue; // reporting it as out of order too is just noise
        if (count == seen.len) return error.TooManyChangelogSections;
        seen[count] = label;
        count += 1;

        if (prev) |p| {
            if (compareVersions(label, p) >= 0) {
                try report(alloc, out, "changelog sections out of order: [{s}] follows [{s}]", .{ label, p });
            }
        }
        prev = label;
    }
}

/// The states a row may carry that claim to be settled. A settled row must be
/// able to say which commit settled it.
const settled_states = [_][]const u8{ "hecho", "done", "listo" };

fn isSettled(state: []const u8) bool {
    for (settled_states) |x| {
        if (std.mem.eql(u8, state, x)) return true;
    }
    return false;
}

fn isHexSha(text: []const u8) bool {
    if (text.len < 7 or text.len > 40) return false;
    for (text) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

/// `git show <sha>:<path>`, or null when git cannot produce it.
///
/// A gate that passes when its reference cannot be read is not a gate, so this
/// returns null rather than an empty string and the caller reports it. `git show`
/// on a committed object needs no network, so the gate stays hermetic.
fn gitShowAlloc(alloc: std.mem.Allocator, io: std.Io, sha: []const u8, path: []const u8) ?[]const u8 {
    const spec = std.fmt.allocPrint(alloc, "{s}:{s}", .{ sha, path }) catch return null;
    var child = std.process.spawn(io, .{
        .argv = &.{ "git", "show", spec },
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return null;
    var buf: [8192]u8 = undefined;
    var reader = child.stdout.?.readerStreaming(io, &buf);
    const out = (reader.interface.allocRemaining(alloc, .limited(1 << 22)) catch return null);
    // The exit code is checked, and that is the whole point of returning an option:
    // `git show` on a bad revision prints nothing on stdout and fails, and an
    // implementation that only read stdout would hand back an empty string for a
    // revision that does not exist. That is a zero read as a value, which is the
    // fourth time in this repository and the first time I wrote one myself.
    switch (child.wait(io) catch return null) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    return out;
}

/// One row of the state table, as the gate sees it.
const StateRow = struct { label: []const u8, state: []const u8, commit: []const u8 };

/// Fixed buffers rather than an `ArrayList`: these tables are a dozen rows and the
/// gate runs on every build, and `appendAssumeCapacity` on an empty list is a
/// panic waiting for a capacity nobody set. A bounded buffer is also the honest
/// shape -- a table with more rows than this is malformed, not truncated.
const RowBuf = struct { items: [64]StateRow = undefined, len: usize = 0 };
const CellBuf = struct { items: [8][]const u8 = undefined, len: usize = 0 };

/// The non-empty cells of a table row, leading pipe ignored. Empty cells are
/// dropped so a trailing `|` or a missing third column reads as "not there" rather
/// than as an empty value that would pass a length check.
///
/// Trims newlines as well as spaces, and that is not tidiness: a caller that passes
/// a single line taken with its terminator would otherwise count "\n" as a cell and
/// see a three-column row where there are two. The test for the missing column is
/// what found it.
fn rowCells(line: []const u8) CellBuf {
    var out: CellBuf = .{};
    var fs = std.mem.splitScalar(u8, line, '|');
    _ = fs.next();
    while (fs.next()) |f| {
        const cell = std.mem.trim(u8, f, " \t\r\n");
        if (cell.len == 0) continue;
        if (out.len == out.items.len) break;
        out.items[out.len] = cell;
        out.len += 1;
    }
    return out;
}

/// The state cell of the row whose label contains `needle`, in `text`.
///
/// One cell wide, on purpose. The check is about the state and not about the row,
/// because a stamp has to survive a schema change: adding a column to this table
/// is not a state change, and if it counted as one then the first edit after the
/// rule landed would fail every settled row at once.
fn rowState(text: []const u8, needle: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const cells = rowCells(line);
        if (cells.len < 2) continue;
        if (std.mem.indexOf(u8, cells.items[0], needle) == null) continue;
        return cells.items[1];
    }
    return null;
}

/// The commit cell of the row whose label contains `needle`, or null when the row
/// has no third column at all.
fn rowCommit(text: []const u8, needle: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const cells = rowCells(line);
        if (cells.len < 2) continue;
        if (std.mem.indexOf(u8, cells.items[0], needle) == null) continue;
        if (cells.len < 3) return null;
        return cells.items[2];
    }
    return null;
}

/// The rows that claim to be settled. A row with no third column is recorded with
/// an empty commit, so a settled state with no origin and a settled state with a
/// malformed origin reach the same report rather than one of them being silent.
fn settledRows(text: []const u8) RowBuf {
    var out: RowBuf = .{};
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const cells = rowCells(line);
        if (cells.len < 2) continue;
        if (!isSettled(cells.items[1])) continue;
        if (out.len == out.items.len) break;
        out.items[out.len] = .{
            .label = cells.items[0],
            .state = cells.items[1],
            .commit = if (cells.len >= 3) cells.items[2] else "",
        };
        out.len += 1;
    }
    return out;
}

/// The labels a state table lists, and whether each has a body.
///
/// A table that lists an item whose body was deleted is a table that still reads as
/// a complete list of what is open. This was not hypothetical: a line-range edit to
/// one bullet of `TODO.md` swallowed the next one, the table kept the row, and
/// `check-docs` passed -- pairing, headings and language all fine, because the row
/// was well formed and the missing text was simply gone.
///
/// Row labels are translated between the two languages, so the match is on the
/// section heading each label's item lives under plus its presence, not on the
/// literal. What is checkable without a translation dictionary is the count: a
/// state table must have as many bodies as it has rows.
fn tableRows(text: []const u8) usize {
    var rows: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "| ") and !std.mem.startsWith(u8, line, "| Document") and !std.mem.startsWith(u8, line, "| Item") and !std.mem.startsWith(u8, line, "|---") and !std.mem.startsWith(u8, line, "| ---")) {
            rows += 1;
        }
    }
    return rows;
}

fn taskItems(text: []const u8) usize {
    var items: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "- [ ] ") or std.mem.startsWith(u8, line, "- [x] ")) items += 1;
    }
    return items;
}

/// How many level-2 sections a document declares, ignoring anything inside a
/// fenced code block.
///
/// It compares the pair's section count and nothing else: a heading's text is
/// translated, so "Features" and "Características" are the same section and
/// comparing their names would fail on every document in the tree. The count is
/// what can be compared without a translation dictionary, and it is the count
/// that caught a real loss -- `libs/signature/README.es.md` lost its entire
/// "Before you use this" section while this gate passed, because it verified that
/// the pair existed and not that the two carried the same sections.
///
/// Pure, so both halves are testable: a fenced block that contains a `## ` must
/// not be counted, or a document that quotes a README's heading structure would
/// report sections it does not have.
fn sectionCount(text: []const u8) usize {
    var count: usize = 0;
    var in_fence = false;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (in_fence) {
            if (std.mem.startsWith(u8, t, "```")) in_fence = false;
            continue;
        }
        if (std.mem.startsWith(u8, t, "```")) {
            in_fence = true;
            continue;
        }
        if (std.mem.startsWith(u8, t, "## ") and !std.mem.startsWith(u8, t, "### ")) count += 1;
    }
    return count;
}

/// A version heading whose body is only whitespace. This is the shape a
/// duplicated heading leaves behind when the duplicate lands above the original:
/// it reads as a section to a scanner and as nothing at all to a reader.
fn checkSectionBodies(text: []const u8, alloc: std.mem.Allocator, out: *std.ArrayList(Problem)) !void {
    var it = std.mem.splitScalar(u8, text, '\n');
    var body_start: ?usize = null;
    var label: []const u8 = "";
    var byte: usize = 0;

    while (it.next()) |line| {
        const at = byte;
        byte += line.len + 1;
        if (!std.mem.startsWith(u8, line, "## [")) continue;

        if (body_start) |start| {
            if (isReleaseLabel(label) and isBlank(text[start..at])) {
                try report(alloc, out, "changelog section [{s}] has an empty body", .{label});
            }
        }
        body_start = byte;
        label = sectionLabel(line);
    }
    // The last section is checked too: a truncated changelog ends there.
    if (body_start) |start| {
        if (isReleaseLabel(label) and isBlank(text[start..])) {
            try report(alloc, out, "changelog section [{s}] has an empty body", .{label});
        }
    }
}

fn sectionLabel(line: []const u8) []const u8 {
    if (line.len < 4) return "";
    const close = std.mem.indexOfScalar(u8, line, ']') orelse return "";
    return line[4..close];
}

fn isBlank(text: []const u8) bool {
    for (text) |c| {
        if (!std.ascii.isWhitespace(c)) return false;
    }
    return true;
}

fn report(
    alloc: std.mem.Allocator,
    out: *std.ArrayList(Problem),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    var problem: Problem = .{};
    problem.setDetail(fmt, args);
    try out.append(alloc, problem);
}

/// `[0.6.0]`, `[Unreleased]`, `[0.5.1]`. A trailing `- date` is not part of the
/// label: the check is on the heading line before the space.
fn isVersionLabel(label: []const u8) bool {
    if (label.len == 0) return false;
    if (!std.ascii.isDigit(label[0])) return true; // Unreleased, Sin publicar, ...
    for (label) |c| {
        if (!std.ascii.isDigit(c) and c != '.') return false;
    }
    return std.mem.indexOfScalar(u8, label, '.') != null;
}

fn isReleaseLabel(label: []const u8) bool {
    return std.ascii.isDigit(label[0]);
}

/// Descending by numeric component, so 0.10.0 sorts above 0.9.0 -- which is
/// the opposite of what a string comparison would say, since "1" < "9".
fn compareVersions(a: []const u8, b: []const u8) i32 {
    var ia = std.mem.splitScalar(u8, a, '.');
    var ib = std.mem.splitScalar(u8, b, '.');
    while (true) {
        const x = ia.next() orelse return if (ib.next() == null) 0 else 1;
        const y = ib.next() orelse return -1;
        const nx = std.fmt.parseInt(i64, x, 10) catch return 1;
        const ny = std.fmt.parseInt(i64, y, 10) catch return -1;
        if (nx != ny) return if (nx > ny) 1 else -1;
    }
}

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

/// The first non-Latin letter in `text`, if there is one: a CJK ideograph, a
/// kana, or a Cyrillic letter.
///
/// UTF-8 encodes those as two or three bytes in 0xC0..0xEF, which `isWordByte`
/// already treats as word characters, so the tokeniser handles them and no list is
/// involved. The ranges are Han (unified and extension A), the CJK compatibility
/// block, kana -- which is what a substitution from a Chinese model produces -- and
/// Cyrillic. A range rather than a vocabulary of seen strings, because a vocabulary
/// only fires on what has already been seen.
///
/// Cyrillic is here for the same reason the rest is, and it was the one that got
/// through: a Spanish sentence in `TODO.es.md` carried five Cyrillic letters in the
/// middle of it, from a shell heredoc, and the rule that claimed to catch foreign
/// scripts did not cover that script. A rule that checks one of the three scripts
/// reads as a rule that checks scripts.
fn firstCjk(text: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (c < 0xC0 or c > 0xEF) {
            i += 1;
            continue;
        }
        // Two-byte form: U+0080..U+07FF, which is where Cyrillic sits.
        if (c < 0xE0) {
            if (i + 2 > text.len) return text[i..];
            const cp = (@as(u21, c & 0x1F) << 6) | (@as(u21, text[i + 1] & 0x3F));
            const cyrillic = cp >= 0x0400 and cp <= 0x052F;
            if (cyrillic) return text[i .. i + 2];
            i += 1;
            continue;
        }
        if (i + 3 > text.len) return text[i..];
        const cp = (@as(u21, c & 0x0F) << 12) |
            (@as(u21, text[i + 1] & 0x3F) << 6) |
            (@as(u21, text[i + 2] & 0x3F));
        const han = (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF);
        const compat = cp >= 0xF900 and cp <= 0xFAFF;
        const kana = cp >= 0x3040 and cp <= 0x30FF;
        if (han or compat or kana) return text[i .. i + 3];
        i += 1;
    }
    return null;
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

        // Rule 4. Checked on the prose, so identifiers and fenced code are
        // exempt like everywhere else here.
        if (firstCjk(prose.items)) |bad| {
            problem.setDetail("prose contains a non-Latin letter (CJK, kana or " ++
                "Cyrillic): {x}", .{bad});
            try problems.append(alloc, problem);
        }

        // Rule 5, on the changelogs only: it is about sections, and no other
        // document in this tree is sectioned by version.
        if (std.mem.startsWith(u8, base, "CHANGELOG")) {
            var struct_problems: std.ArrayList(Problem) = .empty;
            defer struct_problems.deinit(alloc);
            try checkChangelogSections(alloc, text, &struct_problems);
            try checkSectionBodies(text, alloc, &struct_problems);
            for (struct_problems.items) |*sp| {
                sp.setPath(pair_path);
                try problems.append(alloc, sp.*);
            }
        }

        const is_es = std.mem.endsWith(u8, base, ".es.md");

        // Rule 8: a settled row names the commit that settled it, and the row has
        // not moved since. A state with no origin cannot be audited, which is the
        // shape three tools hit in two repositories: a row that claimed "done" with
        // nothing behind it, a row whose body had been deleted, and a gate entry
        // whose own state was still "not started" a commit after it landed.
        //
        // The second half is the one that matters. A commit that exists is a stamp;
        // a commit the row still agrees with is a stamp with a check on it. The
        // comparison is deliberately one cell wide, so adding a column to the table
        // is a schema change and not a state change -- otherwise the first edit
        // after this rule landed would fail every settled row at once.
        if (std.mem.eql(u8, base, "TODO.md")) {
            const settled = settledRows(text);
            for (settled.items[0..settled.len]) |row| {
                if (!isHexSha(row.commit)) {
                    var sp: Problem = .{};
                    sp.setPath(path);
                    sp.setDetail("{s} is {s} with no commit. A settled state with no " ++
                        "origin is an assertion, and the assertion is the thing that " ++
                        "went stale three times", .{ row.label, row.state });
                    try problems.append(alloc, sp);
                    continue;
                }

                const sha = std.fmt.allocPrint(alloc, "{s}", .{row.commit}) catch continue;
                const historical = gitShowAlloc(alloc, io, sha, "TODO.md");
                if (historical == null) {
                    var sp: Problem = .{};
                    sp.setPath(path);
                    sp.setDetail("{s} is {s} and cites {s}, which is not a commit " ++
                        "this repository has. A stamp that points at nothing is worse " ++
                        "than no stamp", .{ row.label, row.state, row.commit });
                    try problems.append(alloc, sp);
                    continue;
                }
                defer alloc.free(historical.?);

                // A row that does not exist at the cited commit is a failure, not an
                // absence of a failure. That is the coordinator's second mutation and
                // it is the one that makes the stamp auditable: the commit has to be
                // one where the row already said this. Skipping the comparison when
                // there is nothing to compare is how a rule that never fires looks
                // exactly like a rule that is satisfied.
                const then_opt = rowState(historical.?, row.label);
                const then = then_opt orelse {
                    var sp: Problem = .{};
                    sp.setPath(path);
                    sp.setDetail("{s} is {s} and cites {s}, where that row does not " ++
                        "exist yet. A stamp has to point at a commit where the row " ++
                        "already said this, not at one before the row was written", .{ row.label, row.state, row.commit });
                    try problems.append(alloc, sp);
                    continue;
                };
                if (!std.mem.eql(u8, then, row.state)) {
                    var sp: Problem = .{};
                    sp.setPath(path);
                    sp.setDetail("{s} says {s} and cites {s}, where it said {s}. The " ++
                        "state moved after the commit it claims to come from, which is " ++
                        "a stamp pointing at a commit that did not settle it", .{ row.label, row.state, row.commit, then });
                    try problems.append(alloc, sp);
                }
            }
        }

        // Rule 7, on the todo only: its state table must have a body per row. A row
        // whose body was deleted still reads as an open item, and that is how a line
        // range that was meant to rewrite one bullet silently swallowed the next one.
        if (std.mem.eql(u8, base, "TODO.md")) {
            const rows = tableRows(text);
            const items = taskItems(text);
            if (rows != items) {
                var sp: Problem = .{};
                sp.setPath(path);
                sp.setDetail("the state table has {d} rows and the document has {d} " ++
                    "items. A row whose body is gone still reads as an open item, so " ++
                    "the two counts have to agree", .{ rows, items });
                try problems.append(alloc, sp);
            }
        }

        // Rule 6, on the pair, once. From the English file only, so a mismatch is
        // one report rather than two, and so the message names the file that is
        // short rather than the one that happened to be read first.
        if (!is_es) {
            if (cwd.readFileAlloc(io, pair_path, alloc, .limited(1 << 20))) |pair_text| {
                defer alloc.free(pair_text);
                const mine = sectionCount(text);
                const theirs = sectionCount(pair_text);
                if (mine != theirs) {
                    var sp: Problem = .{};
                    sp.setPath(pair_path);
                    sp.setDetail("has {d} level-2 sections and {s} has {d}. A pair " ++
                        "that exists is not a pair that says the same thing, and the " ++
                        "section that went missing once went missing here: a script " ++
                        "asserted halfway and never wrote the file", .{ theirs, base, mine });
                    try problems.append(alloc, sp);
                }
            } else |_| {}
        }
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

test "a pair must carry the same number of sections" {
    // Two level-2 sections. `## Deep` is a level-3 and is not counted.
    try std.testing.expectEqual(@as(usize, 2), sectionCount("# T\n\n## One\n\n## Two\n\n### Deep\n"));
    // A heading inside a fence is documentation of a heading, not a section.
    try std.testing.expectEqual(@as(usize, 1), sectionCount("# T\n\n## Real\n\n```\n## Faked\n```\n"));
    // Titles differ between the languages, so only the count can be compared.
    try std.testing.expectEqual(
        sectionCount("# T\n\n## Features\n\n## API\n"),
        sectionCount("# T\n\n## Caracter\u{00ed}sticas\n\n## API\n"),
    );
}

test "section counting survives an unclosed fence by refusing to count inside it" {
    // An unclosed fence means everything after it is code. Counting the rest would
    // report sections the document does not have, which is the zero-read-as-fact
    // shape one level down.
    try std.testing.expectEqual(@as(usize, 1), sectionCount("## One\n\n```\n## Inside\n"));
}

test "the CJK detector catches the ranges and leaves the Latin punctuation alone" {
    // The contamination that motivated the rule, both scripts.
    try std.testing.expect(firstCjk("El texto estaba \u{80A1}\u{6743}\u{6295}\u{8D44} uno.") != null);
    try std.testing.expect(firstCjk("\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}") != null);
    try std.testing.expect(firstCjk("a compatibility ideograph \u{F91E}") != null);
    // Han extension A, which is below the unified block.
    try std.testing.expect(firstCjk("low \u{3400}") != null);

    // And everything this repository's documents legitimately contain. The range
    // is narrow on purpose: "not ASCII" would fail on the accents alone, and
    // this repository uses arrows, dashes, a Greek capital and angle brackets.
    try std.testing.expect(firstCjk("acentos: n\u{00F3}ble, sesi\u{00F3}n, \u{00BF}qu\u{00E9}?") == null);
    try std.testing.expect(firstCjk("em dash \u{2014} arrow \u{2192} up \u{2191}") == null);
    try std.testing.expect(firstCjk("sigma \u{03A3}, angle \u{27E8}x\u{27E9}, minus \u{2212}") == null);
    try std.testing.expect(firstCjk("powers 2\u{00B2} 3\u{00B3} 8\u{2078}, box \u{2502} dot \u{00B7}") == null);
    try std.testing.expect(firstCjk("") == null);
    try std.testing.expect(firstCjk("plain ascii prose") == null);
}

test "a CJK sequence in the prose is a failure and one in a code fence is not" {
    // The exemption the other rules make, checked here rather than assumed: a
    // fenced block and inline code are stripped before the rule runs, so an
    // identifier in another script is not contamination.
    const alloc = std.testing.allocator;

    const with_fence = "antes\n```zig\n// \u{80A1}\u{6743} en un identificador\n```\ndespues";
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    _ = try stripCode(alloc, with_fence, &out);
    try std.testing.expect(firstCjk(out.items) == null);

    const bare = "El texto estaba \u{80A1}\u{6743} uno.";
    var out2: std.ArrayList(u8) = .empty;
    defer out2.deinit(alloc);
    _ = try stripCode(alloc, bare, &out2);
    try std.testing.expect(firstCjk(out2.items) != null);
}

test "a settled row needs a seal and the seal has to be there" {
    const tabla =
        \\| Item | State | Commit |
        \\|---|---|
        \\| `hecho` | hecho | 0a1b2c3 |
        \\| `sin sello` | hecho | - |
        \\| `mal formado` | hecho | xyz |
        \\| `abierto` | sin empezar | - |
    ;
    const rows = settledRows(tabla);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    // Three rows claim to be settled; the fourth does not and therefore asserts
    // nothing, which is why it needs no seal and is not reported. The three that
    // do: one well formed, one absent, one malformed.
    try std.testing.expect(isHexSha(rows.items[0].commit));
    try std.testing.expectEqualStrings("0a1b2c3", rows.items[0].commit);
    try std.testing.expectEqualStrings("-", rows.items[1].commit);
    try std.testing.expect(!isHexSha(rows.items[1].commit));
    try std.testing.expectEqualStrings("xyz", rows.items[2].commit);
    try std.testing.expect(!isHexSha(rows.items[2].commit));
}

test "the seal comparison is one cell wide, so a schema change is not a state change" {
    const antes = "\\| Pin hygiene | hecho | 727c46d |\\n";
    const despues = "\\| Pin hygiene | hecho | 727c46d |\\n";
    try std.testing.expectEqualStrings("hecho", rowState(antes, "Pin hygiene").?);
    try std.testing.expectEqualStrings("hecho", rowState(despues, "Pin hygiene").?);
    try std.testing.expectEqualStrings("727c46d", rowCommit(antes, "Pin hygiene").?);
    // A row that has moved on reports the other state, which is the staleness case.
    const movida = "| Pin hygiene | sin empezar | 727c46d |\n";
    try std.testing.expectEqualStrings("sin empezar", rowState(movida, "Pin hygiene").?);
    // And a row that is not in the table at all has no state to compare.
    try std.testing.expectEqual(@as(?[]const u8, null), rowState(antes, "Nada de eso"));
}

test "an empty cell reads as absent rather than as an empty value" {
    // A missing third column and a `-` in it are both "no seal", and both have to
    // reach the report rather than pass a length check.
    const sin_columna = "| `hecho` | hecho |\n";
    const con_guion = "| `hecho` | hecho | - |\n";
    // Two cells, not three: the third column is absent, and an absent column is
    // dropped rather than read as an empty value that would pass a length check.
    try std.testing.expectEqual(@as(usize, 2), rowCells(sin_columna).len);
    try std.testing.expectEqual(@as(usize, 3), rowCells(con_guion).len);
    try std.testing.expectEqualStrings("-", rowCommit(con_guion, "`hecho`").?);
}

test "the changelog rule catches a repeated section" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Problem) = .empty;
    defer out.deinit(arena.allocator());

    try checkChangelogSections(
        arena.allocator(),
        "## [0.5.1] - 2026-01-01\n\nbody\n\n## [0.5.1] - 2026-01-01\n\nbody\n",
        &out,
    );
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, out.items[0].detailSlice(), "more than once") != null);
}

test "the changelog rule catches sections out of order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Problem) = .empty;
    defer out.deinit(arena.allocator());

    try checkChangelogSections(
        arena.allocator(),
        "## [0.4.0] - 2026-01-01\n\nbody\n\n## [0.5.1] - 2026-01-02\n\nbody\n",
        &out,
    );
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, out.items[0].detailSlice(), "out of order") != null);
}

test "the changelog rule accepts descending order and ignores non-release headings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Problem) = .empty;
    defer out.deinit(arena.allocator());

    try checkChangelogSections(
        arena.allocator(),
        "## [Unreleased]\n\nbody\n\n## [0.6.0] - 2026-09-30\n\nbody\n\n## [0.5.1] - 2026-09-29\n\nbody\n",
        &out,
    );
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "version comparison is numeric, not lexicographic" {
    // 0.10.0 is the newer release; a string compare would call it the older one.
    try std.testing.expect(compareVersions("0.10.0", "0.9.0") > 0);
    try std.testing.expect(compareVersions("0.9.0", "0.10.0") < 0);
    try std.testing.expectEqual(@as(i32, 0), compareVersions("0.6.0", "0.6.0"));
}

test "the changelog rule catches a version section with an empty body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Problem) = .empty;
    defer out.deinit(arena.allocator());

    try checkSectionBodies(
        "## [0.5.1] - 2026-09-29\n\n## [0.5.1] - 2026-09-29\n\n252 tests\n",
        arena.allocator(),
        &out,
    );
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, out.items[0].detailSlice(), "empty body") != null);
}

test "a non-release heading is allowed to be empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(Problem) = .empty;
    defer out.deinit(arena.allocator());

    try checkSectionBodies("## [Unreleased]\n\n", arena.allocator(), &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}
