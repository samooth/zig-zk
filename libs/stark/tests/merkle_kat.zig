// SPDX-License-Identifier: MIT OR Apache-2.0

//! Known-answer tests for the Merkle commitment, pinning the leaf convention.
//!
//! A leaf is `Blake3` of the one-byte field element, an internal node is `Blake3`
//! of its two children concatenated, and the root is the top node. Pinning it
//! guards a bug a differential found and no round-trip test ever could have seen.
//!
//! The local copy of the PCS pre-hashed every element with `hashElement` and
//! then handed the digests to `MerkleTree.init`, which hashes its leaves again.
//! Its leaves were `H(H(v))` and its commitment was a different function, so a
//! proof from one was not readable by a verifier of the other. The end-to-end
//! suite passed throughout, because a round trip is self-consistent: it checks a
//! proof against the same commitment that produced it, double hash and all. A
//! test that only ever agrees with itself cannot see a wrong constant.
//!
//! Both roots were computed outside Zig, with an independent BLAKE3 and the tree
//! rule read off `initFromHashes`, so they are an answer and not a restatement
//! of the implementation. Three lines of Python reproduce them, which is what
//! makes this a known-answer test rather than a snapshot.
//!
//! Two vectors, because each pins a different half of the rule: a one-element
//! commitment's root *is* its leaf, and the four-element one also pins how
//! children are combined. The double-hash answers to these same two vectors were
//! `1257116f82959fbd0...` and `61c8f9615b481f43...`.

const std = @import("std");
const bf = @import("zig-binary-field");

const F = bf.Gf256;

fn expectRoot(table: []const F, expected_hex: []const u8) !void {
    const alloc = std.testing.allocator;
    var tree = try bf.CommittedMlePcsUnsafe(F, F).commit(alloc, table);
    defer tree.deinit();

    var buf: [32]u8 = undefined;
    const expected = try std.fmt.hexToBytes(&buf, expected_hex);
    try std.testing.expectEqualSlices(u8, expected, &tree.root());
}

test "a one-element commitment's root is the leaf, hashed once" {
    try expectRoot(&[_]F{F.fromInt(0x5a)}, "82408a7f2713624a1f3dd742f8e44e5a8181cbdadaa3c05066d1d571ebebbcf6");
}

test "the commitment root pins how children are combined" {
    try expectRoot(
        &[_]F{ F.fromInt(0x00), F.fromInt(0x01), F.fromInt(0x5a), F.fromInt(0xff) },
        "b0f474764351ffafe0b06bb6146f5b4cb448b0ffcbab86368ce77e7e2fd8f344",
    );
}
