const std = @import("std");

/// Hashing utilities for the proof transcript and Merkle commitments.
/// Uses Blake3 under the hood; all functions are deterministic and
/// allocation-free. Field-specific hashing (M31/CM31/QM31) lives in
/// `src/m31/hash.zig` so this module stays field-agnostic.
pub const Hash = struct {
    pub const Digest = [32]u8;
    const Blake3 = std.crypto.hash.Blake3;

    pub fn hashBytes(msg: []const u8) Digest {
        var out: Digest = undefined;
        Blake3.hash(msg, &out, .{});
        return out;
    }

    pub fn hash2(a: Digest, b: Digest) Digest {
        var h = Blake3.init(.{});
        h.update("zig-stark:pair");
        h.update(&a);
        h.update(&b);
        var out: Digest = undefined;
        h.final(&out);
        return out;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "hash known vector (empty input)" {
    // Blake3("")
    const empty = [_]u8{};
    const d = Hash.hashBytes(&empty);
    const expected = [_]u8{
        0xaf, 0x13, 0x49, 0xb9, 0xf5, 0xf9, 0xa1, 0xa6,
        0xa0, 0x40, 0x4d, 0xea, 0x36, 0xdc, 0xc9, 0x49,
        0x9b, 0xcb, 0x25, 0xc9, 0xad, 0xc1, 0x12, 0xb7,
        0xcc, 0x9a, 0x93, 0xca, 0xe4, 0x1f, 0x32, 0x62,
    };
    try std.testing.expectEqualSlices(u8, &expected, &d);
}

// The one vector that cannot be checked without an outside implementation.
// A one-block digest would pass on an implementation whose multi-block or
// multi-chunk path is wrong, and the defect that makes `zig-hash`'s Blake3 not
// BLAKE3 is in exactly that path: its root output recompresses the compressed
// state instead of the input chaining value, which a 2048-byte input walks
// through and a 64-byte one does not reach. The expected value was computed
// with an independent BLAKE3, not with this code.
test "hash known vector across chunks" {
    const msg: []const u8 = "abcdefghijklmnop" ** 128;
    const d = Hash.hashBytes(msg);
    const expected = [_]u8{
        0xb5, 0x41, 0x36, 0xbd, 0xfe, 0x5f, 0x8d, 0x26,
        0x18, 0x33, 0xb9, 0x66, 0x29, 0x17, 0xcd, 0x9c,
        0xc1, 0x57, 0x32, 0x53, 0xa5, 0xbf, 0x8f, 0xd7,
        0xda, 0x35, 0x95, 0x30, 0x9d, 0x9f, 0xfa, 0x5a,
    };
    try std.testing.expectEqualSlices(u8, &expected, &d);
}

// `hash2` is the function every Merkle internal node goes through, and until
// this it had no known-answer vector at all: it was only checked for differing
// from the concatenation of its arguments, which is a statement about this
// module and not about BLAKE3. The value is `Blake3` of the domain tag and the
// two digests, computed independently.
test "hash2 known vector" {
    const a = Hash.hashBytes("a");
    const b = Hash.hashBytes("b");
    const expected = [_]u8{
        0xc9, 0x1b, 0x5b, 0x6f, 0xc7, 0x11, 0xc3, 0x38,
        0x79, 0x3e, 0x54, 0x8a, 0x80, 0xb6, 0x0d, 0xef,
        0xd8, 0xa0, 0x9d, 0x28, 0xc5, 0xd8, 0x8a, 0xba,
        0x2a, 0x54, 0x13, 0xfc, 0x30, 0xf1, 0x28, 0x48,
    };
    try std.testing.expectEqualSlices(u8, &expected, &Hash.hash2(a, b));
}

test "hash is deterministic and sensitive to input" {
    const a = Hash.hashBytes("hello");
    const b = Hash.hashBytes("hello");
    const c = Hash.hashBytes("hellp");
    try std.testing.expectEqualSlices(u8, &a, &b);
    try std.testing.expect(!std.mem.eql(u8, &a, &c));
}

test "hash2 differs from hashing the concatenation" {
    const a = Hash.hashBytes("a");
    const b = Hash.hashBytes("b");
    const c = Hash.hash2(a, b);
    var combined: [64]u8 = undefined;
    @memcpy(combined[0..32], &a);
    @memcpy(combined[32..64], &b);
    const d = Hash.hashBytes(&combined);
    try std.testing.expect(!std.mem.eql(u8, &c, &d));
}
