//! zig-transcript example: simulating a Fiat-Shamir challenge in a ZK protocol.

const std = @import("std");
const transcript = @import("root.zig");

// Minimal F7 field for demonstration
const F7 = struct {
    const Self = @This();
    value: u64,
    pub const modulus: u64 = 7;
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

fn printHex(name: []const u8, bytes: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}: ", .{name});
    for (bytes) |b| try stdout.print("{x:0>2}", .{b});
    try stdout.print("\n", .{});
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== zig-transcript example ===\n\n", .{});

    // --- Basic Transcript ---
    try stdout.print("--- Basic Transcript ---\n", .{});
    var t = transcript.Transcript.init("zk-demo-v1");

    // Simulate a prover sending a commitment
    const commitment = [_]u8{ 0xAB, 0xCD, 0xEF, 0x01 };
    t.absorb(&commitment);
    try stdout.print("Absorbed commitment: ", .{});
    for (commitment) |b| try stdout.print("{x:0>2}", .{b});
    try stdout.print("\n", .{});

    // Verifier (or prover computing the same challenge) squeezes
    var challenge_bytes: [32]u8 = undefined;
    t.squeeze(&challenge_bytes);
    try printHex("Challenge 1", &challenge_bytes);

    // Prover sends a response
    const response = F7.fromInt(5);
    t.absorbField(F7, response);
    try stdout.print("Absorbed response: {}\n", .{response.value});

    // Next challenge
    t.squeeze(&challenge_bytes);
    try printHex("Challenge 2", &challenge_bytes);

    // Field challenge
    const field_challenge = t.squeezeField(F7);
    try stdout.print("Field challenge: {}\n", .{field_challenge.value});

    // --- Forking / Cloning ---
    try stdout.print("\n--- Transcript Forking ---\n", .{});
    var t_fork = transcript.Transcript.init("fork-demo");
    t_fork.absorb("shared-state");

    var t_branch_a = t_fork.clone();
    var t_branch_b = t_fork.clone();

    t_branch_a.absorb("branch-a");
    t_branch_b.absorb("branch-b");

    var out_a: [32]u8 = undefined;
    var out_b: [32]u8 = undefined;
    t_branch_a.squeeze(&out_a);
    t_branch_b.squeeze(&out_b);

    try stdout.print("Branch A challenge: ", .{});
    for (out_a) |b| try stdout.print("{x:0>2}", .{b});
    try stdout.print("\n", .{});

    try stdout.print("Branch B challenge: ", .{});
    for (out_b) |b| try stdout.print("{x:0>2}", .{b});
    try stdout.print("\n", .{});

    try std.testing.expect(!std.mem.eql(u8, &out_a, &out_b));

    // --- Labelled Transcript ---
    try stdout.print("\n--- Labelled Transcript ---\n", .{});
    var lt = transcript.LabelledTranscript.init("zk-labelled-v1");

    lt.absorb("commitment-round-1", &[_]u8{ 0x01, 0x02 });
    lt.absorb("public-input", &[_]u8{ 0xAA, 0xBB });

    const c1 = lt.squeeze("challenge-round-1", F7);
    try stdout.print("Labelled challenge round 1: {}\n", .{c1.value});

    lt.absorbField("prover-response", F7, F7.fromInt(3));
    const c2 = lt.squeeze("challenge-round-2", F7);
    try stdout.print("Labelled challenge round 2: {}\n", .{c2.value});

    // --- Reset ---
    try stdout.print("\n--- Reset ---\n", .{});
    var t_reset = transcript.Transcript.init("reset-demo");
    t_reset.absorb("data");

    var before: [32]u8 = undefined;
    t_reset.squeeze(&before);
    try printHex("Before reset", &before);

    t_reset.reset("reset-demo");
    t_reset.absorb("data");

    var after: [32]u8 = undefined;
    t_reset.squeeze(&after);
    try printHex("After reset ", &after);

    try std.testing.expectEqualSlices(u8, &before, &after);

    try stdout.print("\nAll transcript operations completed successfully!\n", .{});
}
