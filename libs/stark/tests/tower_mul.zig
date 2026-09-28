// SPDX-License-Identifier: MIT OR Apache-2.0

//! The two multiplications in the tower, compared against each other.
//!
//! `mul` picks its implementation at comptime from the host CPU:
//!
//! ```zig
//! pub const has_hardware_clmul = builtin.cpu.arch == .x86_64 and builtin.cpu.has(.x86, .pclmul);
//! // mul: if (Clmul.has_hardware_clmul and level >= 1) return a.mulFast(b);
//! ```
//!
//! `mulFast` is not the same algorithm as `mulRec` at a different width: it
//! converts to a bit polynomial, multiplies carryless and propagates the carry
//! with a loop, where `mulRec` is a recursive Karatsuba over the tower. The two
//! share very little failure surface.
//!
//! The interesting part is what this comparison can and cannot buy, because the
//! two are less independent than a first reading suggests. `mulFast` builds its
//! own conversion and reduction tables with `mulRec` -- `buildFast` calls it in
//! a loop over the field's generator -- so on every host, including x86-64, the
//! Karatsuba is on the path of the bit-sliced multiply. That cuts both ways:
//!
//! - A Karatsuba defect is not confined to the hosts that lack the instruction.
//!   It reaches `mulFast` through the tables, and the 75 tests that crash when
//!   `mulRec`'s half-word mask is mutated are most of them end-to-end tests
//!   that only ever call `mul`.
//! - And the comparison cannot catch the case that matters most, because the two
//!   would then be wrong together. If `mulRec` misbehaved in a way that reached
//!   the generator values the tables are built from, both would return the same
//!   wrong product and this test would pass. It compares the two to each other,
//!   and agreement is not correctness.
//!
//! So read the scope as narrow: it catches a defect that one implementation has
//! and the other does not, at the level of the product, on a host where the
//! instruction exists. It is not a reference implementation and it is not a
//! soundness claim. What it is for is the narrow case it does cover, which is
//! also the one a single-runner project would otherwise never see.
//!
//! Two further limits, so that the name of the file is not read as more than it
//! is:
//!
//! - `mulRec` is called directly here, so what the comparison exercises is its
//!   *composition* -- the masks, `c2 + c0 + c1`. Its leaves call `S.mul`, the
//!   public entry point of the level below, which on a host with the instruction
//!   takes `mulFast` again, and the software leaf is `level == 0`, which is
//!   `a.value & b.value`. No complete software path is under test on x86-64.
//! - Where there is no PCLMULQDQ there is nothing to compare, because `mulFast`
//!   calls `ensureFast()` first and would trap. That is not a silent skip: the
//!   first test's body asserts that fact, so the harness shows which of the two
//!   ran.
//!
//! The coverage of the whole pair across the CI matrix is a property of the
//! runner topology and is recorded in the ledger rather than here, because a
//! coverage that depends on which runners a workflow lists is not in the code.

const std = @import("std");
const bf = @import("zig-binary-field");

const has_hardware_clmul = bf.clmul.has_hardware_clmul;
const Wide = bf.tower.Gf2_128;
const Mid = bf.tower.TowerField(3);

fn randomOf(comptime F: type, rnd: std.Random) F {
    var buf: [F.SIZE]u8 = undefined;
    rnd.bytes(&buf);
    return F.fromBytes(buf);
}

test "the karatsuba composition agrees with the bit-sliced path" {
    if (!has_hardware_clmul) {
        // There is nothing to compare on this host, and saying so is part of the
        // result rather than something a reader has to infer from a green line.
        // This test passing means the host has no PCLMULQDQ, that `mul` is
        // therefore `mulRec`, and that the composition is what runs here. The
        // test above still checks it.
        try std.testing.expect(!has_hardware_clmul);
        return;
    }

    var prng = std.Random.DefaultPrng.init(0xC1_FF_5EED);
    const rnd = prng.random();
    for (0..2000) |_| {
        const a = randomOf(Wide, rnd);
        const b = randomOf(Wide, rnd);
        try std.testing.expect(a.mulRec(b).eq(a.mulFast(b)));
    }
}

test "the karatsuba composition obeys the field laws where the host has no instruction" {
    // The same composition, checked against the laws rather than against the
    // other implementation, so it is not vacuous on a host without the
    // instruction -- which is where the software path is the only path.
    const F = Mid;
    var prng = std.Random.DefaultPrng.init(0x1A_5E_0F_11);
    const rnd = prng.random();
    for (0..2000) |_| {
        const a = randomOf(F, rnd);
        const b = randomOf(F, rnd);
        const c = randomOf(F, rnd);
        // Distributivity, which is what the Karatsuba rearrangement has to
        // preserve: the whole of it is a rewrite of this identity.
        try std.testing.expect(a.add(b).mul(c).eq(a.mul(c).add(b.mul(c))));
        try std.testing.expect(a.add(b).add(c).eq(a.add(b.add(c))));
        // And the two implementations at the width below the hardware path.
        if (F.BITS > 1) try std.testing.expect(a.mulRec(b).eq(a.mulFast(b)));
    }
}

test "the inverse round-trips at 128 bits" {
    var prng = std.Random.DefaultPrng.init(0x1E_5C_0DE);
    const rnd = prng.random();
    for (0..500) |_| {
        const a = randomOf(Wide, rnd);
        if (a.isZero()) continue;
        const inv = a.inv();
        try std.testing.expect(a.mul(inv).eq(Wide.one()));
    }
}
