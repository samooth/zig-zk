//! The published modules, imported by name and called.
//!
//! Every other test in this repository builds its module with its own copy of
//! the import wiring, which is why the root's `zig-stark` module could be
//! missing `zig-parallel` for as long as it was: 255 tests passed and the
//! module an external user gets had never been compiled by anyone. This file
//! imports the five modules the way a caller does -- by the name they are
//! published under, with no wiring of its own beyond the names -- so that gap
//! is closed by something that runs on every `zig build test`.
//!
//! It checks reachability, not behaviour: the consumer in `consumer/` is where
//! the libraries are exercised. This is the cheaper half, and the half that
//! fails first when a module stops being importable.

const std = @import("std");
const commitment = @import("zig-commitment");
const signature = @import("zig-signature");
const snark = @import("zig-snark");
const stark = @import("zig-stark");
const transcript = @import("zig-transcript");

test "every published module resolves" {
    // Names a consumer would reach for. Touching one at comptime is what turns
    // a missing import or a renamed namespace into a build failure instead of a
    // discovery later.
    try std.testing.expect(@hasDecl(transcript, "Channel"));
    try std.testing.expect(@hasDecl(transcript, "Transcript"));
    try std.testing.expect(@hasDecl(commitment, "shamir"));
    try std.testing.expect(@hasDecl(signature, "ed25519"));
    try std.testing.expect(@hasDecl(snark, "verify"));
    try std.testing.expect(@hasDecl(snark, "Groth16"));
    try std.testing.expect(@hasDecl(stark, "m31"));
    try std.testing.expect(@hasDecl(stark, "binius"));
    try std.testing.expect(@hasDecl(stark, "hash"));
}

test "the binius stack instantiates over a 128-bit extension" {
    // `StarkInner` and `BiniusArgWith` reach for `zig-parallel`, which the root
    // build did not hand them. Instantiating here is what noticed.
    const F = stark.binius.tower.Gf16;
    const E = stark.binius.tower.Gf2_128;
    const Stark = stark.binius.stark.BiniusStark(F, E);
    const Adder = stark.binius.adder.Adder(F, E);
    try std.testing.expect(Adder.num_bits > 0);
    try std.testing.expect(@typeInfo(Stark) == .@"struct");
}

test "the m31 field meets the pin's field trait" {
    // `div`, `eql`, `inverse` and `isZero` are the four M31 lacked, and without
    // them `Transcript.squeezeField` rejected the only field in this tree.
    const M31 = stark.m31.M31;
    const traits = @import("zig-algebra-traits");
    traits.assertField(M31);
    try std.testing.expect(M31.div(M31.fromInt(9), M31.fromInt(3)).eq(M31.fromInt(3)));
    try std.testing.expect(M31.fromInt(0).isZero());
}

test "a transcript squeezes a real field" {
    // `squeezeField` read `F.order`, which exists in no field in this tree or
    // in the pin, and `absorbField` read `toInt`, which M31 lacked.
    var t = transcript.Transcript.init("root-api-test");
    t.absorbField(stark.m31.M31, stark.m31.M31.fromInt(7));
    const a = t.squeezeField(stark.m31.M31);
    const b = t.squeezeField(stark.m31.M31);
    try std.testing.expect(!a.eq(b));
}

test "shamir splits over a real field with a caller-supplied source" {
    // `Scalar.random()` took no argument and no field in the tree had one, so
    // this only ever compiled against a test double that returned a constant.
    const M31 = stark.m31.M31;
    var prng = std.Random.DefaultPrng.init(0x1234_5678);
    const shares = try commitment.shamir.split(
        M31,
        M31.fromInt(42),
        2,
        3,
        std.testing.allocator,
        prng.random(),
    );
    defer std.testing.allocator.free(shares);

    const two = [_]commitment.shamir.Share(M31){ shares[0], shares[2] };
    const back = try commitment.shamir.reconstruct(M31, &two);
    try std.testing.expect(back.eq(M31.fromInt(42)));
}

test "a channel can be reset, so a reused one is recoverable" {
    var ch = transcript.Channel.init("root-api-test");
    _ = ch.sample(stark.m31.M31);
    ch.reset("root-api-test");

    var fresh = transcript.Channel.init("root-api-test");
    try std.testing.expect(ch.sample(stark.m31.M31).eq(fresh.sample(stark.m31.M31)));
}
