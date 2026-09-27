// SPDX-License-Identifier: MIT OR Apache-2.0

//! Guards on the binary-field layer this repository consumes rather than owns.
//!
//! The field, tower, polynomial, pack and clmul files come from
//! `zig-binary-field`, and a module's test blocks do not run in a consumer: the
//! forty-one tests those files carried here now run upstream, in their CI. The
//! pin is to a tag, so the exposure is bounded, but a fix release that changed
//! behaviour would reach us through a bump with nothing of ours to notice it.
//!
//! The identity that matters is the MLE fold, and it has to be witnessed over a
//! prime. On a binary field `(1 - r)*a + r*b` and `a + r*(a + b)` are the same
//! function -- `1 - r == 1 + r` and `-a == a` -- so a binary-field test of the
//! fold passes whether the code is generalised or the characteristic-2 rewrite,
//! and cannot fail. Upstream guards this with its own prime fixture; these are
//! the guards on our side of the pin, and M31 is a 31-bit prime already available
//! through `zig-field`, whose products stay inside u64 so the expected values
//! here are computed rather than carried over from anywhere.

const std = @import("std");
const bf = @import("zig-binary-field");
const M31 = @import("zig-field").M31;

/// Fold `vals` in place over `r` with the general form `(1 - r)*a + r*b`, and
/// return the head. Correct over any field.
fn foldGeneral(comptime F: type, vals: []F, r: []const F) F {
    var len = vals.len;
    for (r) |ri| {
        const half = len / 2;
        for (0..half) |i| {
            const a = vals[2 * i];
            const b = vals[2 * i + 1];
            vals[i] = F.one().sub(ri).mul(a).add(ri.mul(b));
        }
        len = half;
    }
    return vals[0];
}

/// The same fold in the form the code used to compute it, which is identical
/// over a binary field and wrong over a prime.
fn foldChar2(comptime F: type, vals: []F, r: []const F) F {
    var len = vals.len;
    for (r) |ri| {
        const half = len / 2;
        for (0..half) |i| {
            const a = vals[2 * i];
            const b = vals[2 * i + 1];
            vals[i] = a.add(ri.mul(a.add(b)));
        }
        len = half;
    }
    return vals[0];
}

test "the MLE fold is (1 - r)*a + r*b and not the characteristic-2 rewrite" {
    const alloc = std.testing.allocator;

    // Four points over two variables, so the fold runs twice per evaluation
    // and one wrong step cannot average out.
    const evals = [_]M31{ M31.fromInt(3), M31.fromInt(11), M31.fromInt(7), M31.fromInt(19) };
    const r = [_]M31{ M31.fromInt(5), M31.fromInt(13) };

    const poly = bf.Multilinear(M31){ .evals = &evals };
    const got = try poly.eval(alloc, &r);

    const scratch_general = try alloc.dupe(M31, &evals);
    defer alloc.free(scratch_general);
    const expected = foldGeneral(M31, scratch_general, &r);
    try std.testing.expect(expected.eq(got));

    // This is the assertion with teeth, and the reason the identity cannot be
    // checked on a binary field: the characteristic-2 rewrite is what the code
    // used to compute, and over a prime it is a different number. If someone
    // reverts the fold, this fails while the assertion above still passes.
    const scratch_char2 = try alloc.dupe(M31, &evals);
    defer alloc.free(scratch_char2);
    const char2 = foldChar2(M31, scratch_char2, &r);
    try std.testing.expect(!char2.eq(got));
}

test "the adopted field inverts, and the checked variant refuses zero" {
    const F = bf.Gf256;
    const a = F.fromInt(0b1011_0110);
    const inv = try a.invChecked();
    try std.testing.expect(a.mul(inv).eq(F.one()));

    // The total inverse is a legacy wrapper that answers zero for zero over a
    // binary field, which is why a caller dividing by untrusted input wants the
    // checked variant. Its error is upstream's name, not ours.
    try std.testing.expectError(error.InverseOfZero, F.zero().invChecked());
}

test "the adopted tower is a field" {
    const F = bf.Gf256;
    var prng = std.Random.DefaultPrng.init(0x5EED_C0DE);
    const rnd = prng.random();
    for (0..200) |_| {
        const a = F.fromInt(rnd.int(u32));
        const b = F.fromInt(rnd.int(u32));
        const c = F.fromInt(rnd.int(u32));
        // Distributivity and associativity, which is what makes the fold's
        // in-place reassociation safe.
        try std.testing.expect(a.add(b).mul(c).eq(a.mul(c).add(b.mul(c))));
        try std.testing.expect(a.add(b).add(c).eq(a.add(b.add(c))));
    }
}
