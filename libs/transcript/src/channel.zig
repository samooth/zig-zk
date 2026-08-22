// SPDX-License-Identifier: MIT OR Apache-2.0

//! Duck-typed Fiat-Shamir channel (zig-stark style).
//!
//! A field-agnostic channel that absorbs any serializable value through its
//! `SIZE`, `toBytes`, `fromBytes` interface. No field traits required.
//! This is the zig-stark `Channel` pattern, using Blake3 as the sponge.
//!
//! # Differences from `Transcript`
//! - **Duck-typed**: Absorbs any type with `SIZE`, `toBytes(&[SIZE]u8)`, `fromBytes([SIZE]u8)`
//! - **No length prefix** on raw bytes (relies on type size for domain separation)
//! - **No `clone`/`reset`/`LabelledTranscript`** — minimal core only
//! - **Has `sampleIndex`** — uniform random index in [0, n)

const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;

/// Fiat-Shamir channel backed by Blake3.
///
/// Absorbs values via their `SIZE`/`toBytes`/`fromBytes` interface.
/// Samples challenges by deriving bytes from transcript state and
/// absorbing them back (Fiat-Shamir).
pub const Channel = struct {
    hasher: Blake3,

    pub fn init(domain_separator: []const u8) Channel {
        var h = Blake3.init(.{});
        h.update("zig-stark:channel");
        h.update(domain_separator);
        return .{ .hasher = h };
    }

    /// Absorb raw bytes.
    pub fn absorbBytes(self: *Channel, data: []const u8) void {
        self.hasher.update(data);
    }

    /// Absorb a single serializable element.
    ///
    /// `T` must expose:
    /// - `SIZE: usize` — byte length
    /// - `toBytes(*[SIZE]u8) void`
    pub fn absorb(self: *Channel, value: anytype) void {
        const T = @TypeOf(value);
        var buf: [T.SIZE]u8 = undefined;
        value.toBytes(&buf);
        self.hasher.update(&buf);
    }

    /// Absorb a slice of serializable elements.
    pub fn absorbMany(self: *Channel, values: anytype) void {
        for (values) |v| self.absorb(v);
    }

    /// Derive `out.len` challenge bytes and absorb them back.
    /// Ensures later samples are always fresh (correct Fiat-Shamir).
    pub fn sampleBytes(self: *Channel, out: []u8) void {
        var counter: u64 = 0;
        var remaining = out;
        while (remaining.len > 0) {
            var snapshot = self.hasher;
            snapshot.update("zig-stark:sample");
            var cbuf: [8]u8 = undefined;
            std.mem.writeInt(u64, &cbuf, counter, .little);
            snapshot.update(&cbuf);
            var block: [32]u8 = undefined;
            snapshot.final(&block);
            self.hasher.update(&block);
            const n = @min(remaining.len, block.len);
            @memcpy(remaining[0..n], block[0..n]);
            remaining = remaining[n..];
            counter += 1;
        }
    }

    /// Sample a random element of a serializable type `T`.
    ///
    /// `T` must expose `SIZE`, `toBytes`, `fromBytes([SIZE]u8) T`.
    pub fn sample(self: *Channel, comptime T: type) T {
        var buf: [T.SIZE]u8 = undefined;
        self.sampleBytes(&buf);
        return T.fromBytes(buf);
    }

    /// Sample a uniform random index in [0, n).
    pub fn sampleIndex(self: *Channel, n: usize) usize {
        std.debug.assert(n > 0);
        const bits: usize = @intCast(std.math.log2_int(usize, n) + 1);
        const bytes_needed = (bits + 7) / 8;
        var buf: [8]u8 = undefined;
        self.sampleBytes(buf[0..bytes_needed]);
        var value: usize = 0;
        for (0..bytes_needed) |i| {
            value = (value << 8) | buf[i];
        }
        // rejection-sample a uniform value in [0, n)
        const mask: usize = (@as(usize, 1) << @intCast(bits)) - 1;
        var v = value & mask;
        while (v >= n) {
            self.sampleBytes(buf[0..bytes_needed]);
            value = 0;
            for (0..bytes_needed) |i| {
                value = (value << 8) | buf[i];
            }
            v = value & mask;
        }
        return v;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Test type that satisfies the serializable interface
const TestElem = struct {
    const Self = @This();
    pub const SIZE = 4;
    value: u32,

    pub fn toBytes(self: Self, out: *[SIZE]u8) void {
        std.mem.writeInt(u32, out[0..], self.value, .little);
    }
    pub fn fromBytes(bytes: [SIZE]u8) Self {
        return .{ .value = std.mem.readInt(u32, bytes[0..], .little) };
    }
    pub fn eql(a: Self, b: Self) bool {
        return a.value == b.value;
    }
};

test "channel sampling is deterministic for same transcript" {
    var c1 = Channel.init("test");
    var c2 = Channel.init("test");
    c1.absorb(TestElem{ .value = 7 });
    c2.absorb(TestElem{ .value = 7 });
    try testing.expect(c1.sample(TestElem).eql(c2.sample(TestElem)));
}

test "channel sampling differs across transcripts" {
    var c1 = Channel.init("test");
    var c2 = Channel.init("test");
    c1.absorb(TestElem{ .value = 7 });
    c2.absorb(TestElem{ .value = 8 });
    try testing.expect(!c1.sample(TestElem).eql(c2.sample(TestElem)));
}

test "channel sampleIndex is in range" {
    var c = Channel.init("idx");
    const sizes = [_]usize{ 1, 2, 3, 7, 8, 100, 1024 };
    for (sizes) |n| {
        var i: usize = 0;
        while (i < 50) : (i += 1) {
            const v = c.sampleIndex(n);
            try testing.expect(v < n);
        }
    }
}

test "channel sampleIndex covers range roughly uniformly" {
    var c = Channel.init("uniform");
    const n = 8;
    var counts = [_]usize{0} ** 8;
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        const v = c.sampleIndex(n);
        std.debug.assert(v < n);
        counts[v] += 1;
    }
    for (counts) |cnt| {
        // 4000/8 = 500 expected; allow wide margin
        try testing.expect(cnt > 200 and cnt < 800);
    }
}
