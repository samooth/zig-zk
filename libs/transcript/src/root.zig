//! zig-transcript: Fiat-Shamir transcripts for non-interactive zero-knowledge proofs.
//!
//! Provides deterministic, stateful absorb-squeeze transcripts backed by Blake3.
//!
//! # Modules
//! - `Transcript`: Core Fiat-Shamir transcript.
//! - `LabelledTranscript`: Domain-separated transcript with explicit labels.
//! - `Channel`: duck-typed channel used by `zig-stark`; absorbs anything with
//!   `SIZE`/`toBytes`/`fromBytes`, no field trait required.
//!
//! # Quick Start
//! ```zig
//! const transcript = @import("zig-transcript");
//!
//! var t = transcript.Transcript.init("my_protocol_v1");
//! t.absorb(&public_input);
//! t.absorbField(F, commitment);
//! const challenge = t.squeezeField(F);
//! ```

const std = @import("std");

pub const transcript = @import("transcript.zig");
pub const channel = @import("channel.zig");

pub const Transcript = transcript.Transcript;
pub const LabelledTranscript = transcript.LabelledTranscript;
pub const Channel = channel.Channel;

// ============================================================================
// Tests
// ============================================================================

// Minimal F7 field for testing
const F7 = struct {
    const Self = @This();
    value: u64,
    pub const modulus: u64 = 7;
    pub const characteristic: u64 = 7;
    pub const order: u64 = 7;

    pub fn zero() Self {
        return .{ .value = 0 };
    }
    pub fn one() Self {
        return .{ .value = 1 };
    }
    pub fn fromInt(x: u256) Self {
        return .{ .value = @intCast(x % modulus) };
    }
    pub fn toInt(self: Self) u256 {
        return self.value;
    }
    pub fn eql(a: Self, b: Self) bool {
        return a.value == b.value;
    }
    pub fn add(a: Self, b: Self) Self {
        return fromInt(a.value + b.value);
    }
    pub fn sub(a: Self, b: Self) Self {
        return fromInt(a.value + (modulus - b.value % modulus));
    }
    pub fn neg(a: Self) Self {
        return if (a.value == 0) zero() else fromInt(modulus - a.value);
    }
    pub fn mul(a: Self, b: Self) Self {
        return fromInt(a.value * b.value);
    }
    pub fn inv(a: Self) Self {
        std.debug.assert(!a.isZero());
        return pow(a, modulus - 2);
    }
    pub const inverse = inv;
    pub fn div(a: Self, b: Self) Self {
        return mul(a, inv(b));
    }
    pub fn pow(base: Self, exp: u64) Self {
        var result = one();
        var b = base;
        var e = exp;
        while (e > 0) {
            if (e & 1 == 1) result = mul(result, b);
            b = mul(b, b);
            e >>= 1;
        }
        return result;
    }
    pub fn isZero(self: Self) bool {
        return self.value == 0;
    }
    pub fn random() Self {
        return fromInt(1);
    }
};

test "Transcript deterministic squeeze" {
    var t1 = Transcript.init("test-protocol");
    var t2 = Transcript.init("test-protocol");

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t1.squeeze(&out1);
    t2.squeeze(&out2);

    try std.testing.expectEqualSlices(u8, &out1, &out2);
}

test "Transcript different labels produce different output" {
    var t1 = Transcript.init("protocol-a");
    var t2 = Transcript.init("protocol-b");

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t1.squeeze(&out1);
    t2.squeeze(&out2);

    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "Transcript absorb changes squeeze output" {
    var t1 = Transcript.init("test");
    var t2 = Transcript.init("test");
    t2.absorb("extra data");

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t1.squeeze(&out1);
    t2.squeeze(&out2);

    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "Transcript multiple squeezes are different" {
    var t = Transcript.init("test");

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t.squeeze(&out1);
    t.squeeze(&out2);

    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "Transcript absorbField and squeezeField" {
    var t = Transcript.init("field-test");
    t.absorbField(F7, F7.fromInt(3));

    const c1 = t.squeezeField(F7);
    const c2 = t.squeezeField(F7);

    // Both should be valid field elements
    try std.testing.expect(c1.value < 7);
    try std.testing.expect(c2.value < 7);
    // And different
    try std.testing.expect(!F7.eql(c1, c2));
}

test "Transcript clone produces identical output" {
    var t1 = Transcript.init("clone-test");
    t1.absorb("data");

    var t2 = t1.clone();

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t1.squeeze(&out1);
    t2.squeeze(&out2);

    try std.testing.expectEqualSlices(u8, &out1, &out2);
}

test "Transcript clone diverges after absorb" {
    var t1 = Transcript.init("clone-test");
    var t2 = t1.clone();

    t1.absorb("extra");

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    t1.squeeze(&out1);
    t2.squeeze(&out2);

    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "Transcript reset" {
    var t = Transcript.init("reset-test");
    t.absorb("data");

    var out1: [32]u8 = undefined;
    t.squeeze(&out1);

    t.reset("reset-test");
    t.absorb("data");

    var out2: [32]u8 = undefined;
    t.squeeze(&out2);

    try std.testing.expectEqualSlices(u8, &out1, &out2);
}

test "Transcript squeezeU64" {
    var t = Transcript.init("u64-test");
    const v1 = t.squeezeU64();
    const v2 = t.squeezeU64();
    try std.testing.expect(v1 != v2);
}

test "Transcript squeezeU256" {
    var t = Transcript.init("u256-test");
    const v1 = t.squeezeU256();
    const v2 = t.squeezeU256();
    try std.testing.expect(v1 != v2);
}

test "LabelledTranscript domain separation" {
    var lt = LabelledTranscript.init("protocol-v1");
    lt.absorb("commitment", &[_]u8{ 1, 2, 3 });
    lt.absorb("public-input", &[_]u8{ 4, 5, 6 });

    const c1 = lt.squeeze("challenge-1", F7);
    const c2 = lt.squeeze("challenge-2", F7);

    try std.testing.expect(c1.value < 7);
    try std.testing.expect(c2.value < 7);
    try std.testing.expect(!F7.eql(c1, c2));
}

test "LabelledTranscript same data different labels produce different challenges" {
    var lt1 = LabelledTranscript.init("protocol-v1");
    var lt2 = LabelledTranscript.init("protocol-v1");

    lt1.absorb("label-a", &[_]u8{ 1, 2, 3 });
    lt2.absorb("label-b", &[_]u8{ 1, 2, 3 });

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    lt1.squeezeBytes("challenge", &out1);
    lt2.squeezeBytes("challenge", &out2);

    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "LabelledTranscript clone" {
    var lt1 = LabelledTranscript.init("protocol-v1");
    lt1.absorb("commitment", &[_]u8{ 1, 2, 3 });

    var lt2 = lt1.clone();

    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    lt1.squeezeBytes("challenge", &out1);
    lt2.squeezeBytes("challenge", &out2);

    try std.testing.expectEqualSlices(u8, &out1, &out2);
}

test "Transcript absorbFieldSlice" {
    var t = Transcript.init("slice-test");
    const fields = [_]F7{ F7.fromInt(1), F7.fromInt(2), F7.fromInt(3) };
    t.absorbFieldSlice(F7, &fields);

    const c = t.squeezeField(F7);
    try std.testing.expect(c.value < 7);
}
