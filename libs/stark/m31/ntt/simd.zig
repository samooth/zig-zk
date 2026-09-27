const std = @import("std");
const M31 = @import("../field/m31.zig").M31;
const classic = @import("classic.zig");

/// SIMD butterfly placeholder.
///
/// A true vectorized NTT is not possible over M31 beyond size 2 (the field's
/// multiplicative group has 2-adicity 1). The SIMD-friendly transform on this
/// field is the circle FFT (see `ntt/circle.zig` and `field/m31.zig` Vec8 ops).
/// This module currently delegates to the scalar NTT and is only valid for
/// `a.len <= 2`.
/// Propagates nttClassic's `error.InvalidLength`. The assert that used to be
/// here was weaker than the one in the function it delegates to: it allowed a
/// length of zero, which nttClassic rejects. Checking it twice meant the error
/// could come from either place, and the weaker one first.
pub fn simdButterfly(a: []M31, invert: bool) error{InvalidLength}!void {
    try classic.nttClassic(a, invert);
}

test "simd butterfly round-trip (n = 2)" {
    const alloc = std.testing.allocator;
    const input = [_]M31{ M31.fromInt(4), M31.fromInt(1) };
    var work = try alloc.dupe(M31, &input);
    defer alloc.free(work);

    try simdButterfly(work, false);
    try simdButterfly(work, true);
    try std.testing.expect(work[0].eq(input[0]));
    try std.testing.expect(work[1].eq(input[1]));
}

test "simd butterfly matches classic NTT (n = 2)" {
    const alloc = std.testing.allocator;
    const input = [_]M31{ M31.fromInt(9), M31.fromInt(4) };

    var a = try alloc.dupe(M31, &input);
    defer alloc.free(a);
    const b = try alloc.dupe(M31, &input);
    defer alloc.free(b);

    try simdButterfly(a, false);
    try classic.nttForward(b);
    try std.testing.expect(a[0].eq(b[0]));
    try std.testing.expect(a[1].eq(b[1]));

    try simdButterfly(a, true);
    try classic.nttInverse(b);
    try std.testing.expect(a[0].eq(b[0]));
    try std.testing.expect(a[1].eq(b[1]));
}

test "simd butterfly n = 1 is identity" {
    var v = [_]M31{M31.fromInt(7)};
    try simdButterfly(&v, false);
    try simdButterfly(&v, true);
    try std.testing.expect(v[0].eq(M31.fromInt(7)));
}

test "simdButterfly propagates the length error from the transform it delegates to" {
    const alloc = std.testing.allocator;
    var three: [3]M31 = undefined;
    @memset(&three, M31.one());
    // The assert this used to carry allowed a length of zero and rejected
    // nothing else that the delegated check would not, so the error has to come
    // from the callee for the constraint to be the one that is actually stated.
    try std.testing.expectError(error.InvalidLength, simdButterfly(&three, false));
    try std.testing.expectError(error.InvalidLength, simdButterfly(&three, true));

    const one = [_]M31{M31.fromInt(7)};
    const work = try alloc.dupe(M31, &one);
    defer alloc.free(work);
    try simdButterfly(work, false);
    try simdButterfly(work, true);
}
