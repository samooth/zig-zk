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
//! - **Has `sampleIndex`** — uniform random index in [0, n), `error.EmptyRange`
//!   when `n == 0`

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

    /// Return the channel to the state it had right after `init`, discarding
    /// everything absorbed since.
    ///
    /// A channel is stateful, so a prover and a verifier that share one
    /// instance sample different challenges and the verifier returns false with
    /// no error anywhere. That failure has no message: it looks like a wrong
    /// proof rather than a wrong channel. Two channels with one label is the
    /// correct way, and this exists so that the wrong way is recoverable
    /// instead of mysterious.
    pub fn reset(self: *Channel, domain_separator: []const u8) void {
        self.* = Channel.init(domain_separator);
    }

    /// Absorb raw bytes.
    pub fn absorbBytes(self: *Channel, data: []const u8) void {
        self.hasher.update(data);
    }

    /// Absorb a Merkle digest (any array-of-u8 container exposing its bytes,
    /// e.g. `[32]u8`).
    pub fn absorbDigest(self: *Channel, digest: anytype) void {
        self.hasher.update(&digest);
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
    ///
    /// `error.EmptyRange` for `n == 0`: there is no uniform distribution over
    /// an empty set, and `log2_int(usize, 0)` is undefined, so this is a caller
    /// mistake rather than something to paper over.
    pub fn sampleIndex(self: *Channel, n: usize) error{EmptyRange}!usize {
        if (n == 0) return error.EmptyRange;
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
            const v = try c.sampleIndex(n);
            try testing.expect(v < n);
        }
    }
}

test "channel sampleIndex refuses an empty range" {
    var c = Channel.init("vacio");
    try testing.expectError(error.EmptyRange, c.sampleIndex(0));
}

test "channel sampleIndex covers range roughly uniformly" {
    var c = Channel.init("uniform");
    const n = 8;
    var counts = [_]usize{0} ** 8;
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        const v = try c.sampleIndex(n);
        try std.testing.expect(v < n);
        counts[v] += 1;
    }
    for (counts) |cnt| {
        // 4000/8 = 500 expected; allow wide margin
        try testing.expect(cnt > 200 and cnt < 800);
    }
}

// ---------------------------------------------------------------------------
// The transcript invariant.
//
// This is the cause, not the symptom. A proof hash changes if the transcript
// changes, so a proof-hash invariant would catch the change one step late and
// without saying which of the two moved. Pinning the transcript pins the thing a
// release is most likely to disturb by accident: a domain separator, a label, an
// absorb order, the hash itself.
//
// The constant has two halves and both matter. The constant is the first: it
// fails when anything in the sponge moves. The two checks after it are the
// second, because an invariant nobody has seen move is not known to be watching
// anything -- and a test that only ever passes is a test that would also pass if
// it compared a number to itself.
//
// The absorbed values are `[SIZE]u8` arrays rather than strings, because this
// channel is duck-typed: it absorbs anything with `SIZE` and `toBytes`, which is
// what makes the sequence below an ordinary protocol transcript rather than
// something shaped to the test.
// ---------------------------------------------------------------------------

/// An absorbed value. The channel is duck-typed, so this is what an absorbed
/// type looks like: a declared `SIZE` and `toBytes`. The `SIZE` is not a power of
/// two on purpose -- the channel documents that it puts no length prefix on what
/// it absorbs and relies on the type's own width for separation, and a width that
/// is not a power of two is where that claim is testable.
fn Fixed(comptime N: comptime_int) type {
    return struct {
        const Self = @This();
        pub const SIZE = N;
        b: [N]u8,

        pub fn toBytes(self: Self, out: *[N]u8) void {
            out.* = self.b;
        }

        pub fn fromBytes(b: [N]u8) Self {
            return .{ .b = b };
        }
    };
}

const Word24 = Fixed(24);
const Word32 = Fixed(32);

fn word24(comptime fill: u8) Word24 {
    var w: Word24 = .{ .b = undefined };
    @memset(&w.b, fill);
    return w;
}

fn word32(comptime fill: u8) Word32 {
    var w: Word32 = .{ .b = undefined };
    @memset(&w.b, fill);
    return w;
}

/// The digest of the sequence below. If the sponge, the domain separator, the
/// absorb order or the absorbed width moves this, it moves because the transcript
/// moved -- and nothing else in the tree is allowed to move it.
const channel_digest = 0xe5a4174e79b3748b;

fn digestOf(ch: *Channel) u64 {
    var out: [32]u8 = undefined;
    ch.sampleBytes(&out);
    return std.hash.Wyhash.hash(0, &out);
}

test "the transcript invariant: a fixed sequence has a fixed digest" {
    var ch = Channel.init("zig-zk:transcript-invariant");
    ch.absorb(word32(0x01));
    ch.absorb(word32(0x02));
    ch.absorb(word32(0x03));
    try std.testing.expectEqual(channel_digest, digestOf(&ch));
}

test "the transcript invariant discriminates on the domain separator" {
    // Axis one, the transcript itself. A different domain separator is a
    // different transcript, and a challenge carried across two of them is the
    // cross-protocol reuse the separator exists to prevent.
    var a = Channel.init("zig-zk:transcript-invariant");
    var b = Channel.init("zig-zk:transcript-invarianT");
    a.absorb(word32(0x01));
    b.absorb(word32(0x01));
    try std.testing.expect(digestOf(&a) != digestOf(&b));
}

test "the transcript invariant discriminates on the absorbed values" {
    // Same label, different statement. Two instances must not reach the same
    // challenge, and the only thing separating them is what went into the sponge.
    var a = Channel.init("zig-zk:transcript-invariant");
    var b = Channel.init("zig-zk:transcript-invariant");
    a.absorb(word32(0x01));
    b.absorb(word32(0x02));
    try std.testing.expect(digestOf(&a) != digestOf(&b));
}

test "the transcript invariant discriminates on absorb order" {
    // The same two values in the other order. A sponge that forgets order would
    // let a statement be transposed without moving anything, which is the whole
    // reason the sequence of absorbs is part of the statement rather than a detail
    // of how it is written down.
    var a = Channel.init("zig-zk:transcript-invariant");
    var b = Channel.init("zig-zk:transcript-invariant");
    a.absorb(word32(0x01));
    a.absorb(word32(0x02));
    b.absorb(word32(0x02));
    b.absorb(word32(0x01));
    try std.testing.expect(digestOf(&a) != digestOf(&b));
}

// KNOWN DEFECT, recorded rather than fixed. See SECURITY.md.
//
// The channel puts no length prefix on what it absorbs -- all three of
// `absorb`, `absorbBytes` and `absorbDigest` are a bare `hasher.update` -- and
// its own documentation says the type's width is what provides domain
// separation. That claim is false, and this is the counterexample: a 24-byte
// value followed by a 32-byte value reaches the sponge as the same 56 bytes as
// one 56-byte value, so two different statements reach the same challenge.
//
// Asserted so that it is a fact the suite carries rather than a note somebody
// reads once. When the channel gains a length prefix this test fails, which is
// the point: the fix is a BREAKING change to every transcript and every proof
// this repository has produced, and it should fail loudly when it happens.
//
// Not reachable through the protocols here today. The verifier knows how many
// digests to expect from the AIR and how long the public input is, so it can
// find the boundaries. It is reachable for the next protocol that absorbs two
// types of different widths, which is exactly what this channel invites.

test "KNOWN DEFECT: type width does not separate, because nothing is length-prefixed" {
    const Word56 = Fixed(56);
    var split = Channel.init("zig-zk:probe");
    split.absorb(word24(0xAA));
    split.absorb(word32(0xBB));

    var whole = Channel.init("zig-zk:probe");
    var b56: Word56 = .{ .b = undefined };
    @memset(b56.b[0..24], 0xAA);
    @memset(b56.b[24..56], 0xBB);
    whole.absorb(b56);

    try std.testing.expectEqual(digestOf(&split), digestOf(&whole));
}
