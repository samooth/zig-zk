//! Groth16 verifier + reference prover over BN254.
//!
//! `verify` is the primitive consumers should call: allocation-free and safe
//! against malformed input. `Groth16` wraps it with a reference prover for
//! compile-time-sized rank-1 constraint systems. That prover is a test oracle,
//! not a production prover, and the three reasons are the same reason: it is a
//! reference, not something to deploy.
//!
//! It is not constant time. Blinding factors come from the caller, so nothing here
//! draws from a source the prover controls, and the scalar multiplication is a
//! single multiplication where a real prover uses MSMs -- which is a cost shape, not
//! only a timing one. Neither reaches `verify`, which is the primitive a consumer
//! should call and is public-input only: every input to it is public by
//! construction.
const std = @import("std");
const zc = @import("zig-curve");
const tp = @import("zig-pairing").bn254_tower_pairing;

pub const Fr = zc.bn254.Fr;
pub const G1 = zc.bn254.G1;
pub const G2 = zc.bn254.G2;
pub const Fp12T = tp.Fp12T;

pub const g1_gen = zc.bn254.G1_generator;
pub const g2_gen = zc.bn254.G2_generator;

fn smG1(p: G1, s: Fr) G1 {
    return p.scalarMul(s.toU512());
}

fn smG2(p: G2, s: Fr) G2 {
    return p.scalarMul(s.toU512());
}

/// Groth16 verification:
/// `e(A, B) == e(alpha, beta) * e(C, delta) * e(PV, gamma)`.
///
/// `ic[0]` encodes the constant-one wire of the circuit; `ic[i + 1]` encodes
/// public input `i`, whose value is supplied in `pub_in`. A length mismatch
/// between `ic` and `pub_in` means a malformed proof and verifies as false.
///
/// The verifying key is assumed trustworthy; the proof elements are not, so
/// they are checked for curve and prime-order-subgroup membership before use.
pub fn verify(
    a1: G1,
    b2: G2,
    g2: G2,
    d2: G2,
    ic: []const G1,
    pa: G1,
    pb: G2,
    pc: G1,
    pub_in: []const Fr,
) bool {
    if (ic.len == 0 or pub_in.len + 1 != ic.len) return false;

    // The pairing yields the identity for points off the curve or outside the
    // prime-order subgroup, which would silently drop one term of the check
    // instead of rejecting the proof.
    if (!tp.isG1InSubgroup(pa)) return false;
    if (!tp.isG2InSubgroup(pb)) return false;
    if (!tp.isG1InSubgroup(pc)) return false;

    var pv = ic[0];
    for (pub_in, 0..) |pi, i| pv = pv.add(smG1(ic[i + 1], pi));

    const lhs = tp.pairing(pa.neg(), pb);
    const ab = tp.pairing(a1, b2);
    const cd = tp.pairing(pc, d2);
    const pv_g = tp.pairing(pv, g2);
    return lhs.mul(ab).mul(cd).mul(pv_g).eql(Fp12T.one());
}

/// Reference Groth16 over a rank-1 constraint system with compile-time
/// dimensions.
///
/// The system has `n_wires` wires and `n_constraints` constraints of the form
/// `a . z * b . z = c . z`. `ic_wires` lists the wires whose values the
/// verifier knows: `ic_wires[0]` is the constant-one wire, the remaining
/// entries are the public inputs in order. Every other wire is private and
/// only ever appears inside the proof's `c` element.
pub fn Groth16(
    comptime ic_wires: []const usize,
    comptime n_constraints: usize,
    comptime n_wires: usize,
) type {
    // A `std.debug.assert` here would be compiled out in ReleaseFast, where a
    // malformed system would still build and then fail on the first proof. The
    // arguments are comptime, so the only honest way to refuse is to refuse at
    // compile time and say which argument is wrong.
    comptime {
        if (n_constraints == 0) @compileError("Groth16: n_constraints must be > 0");
        if (n_wires == 0) @compileError("Groth16: n_wires must be > 0");
        if (ic_wires.len < 1) @compileError("Groth16: ic_wires must list at least the constant-one wire");
        if (ic_wires.len > n_wires) @compileError("Groth16: ic_wires lists more wires than the system has");
        for (ic_wires, 0..) |w, i| {
            if (w >= n_wires) @compileError("Groth16: ic_wires[" ++ std.fmt.comptimePrint("{d}", .{i}) ++ "] is out of range for n_wires");
            for (ic_wires[0..i], 0..) |prev, j| {
                if (prev == w) @compileError("Groth16: ic_wires lists wire " ++ std.fmt.comptimePrint("{d}", .{w}) ++ " twice (at " ++ std.fmt.comptimePrint("{d}", .{j}) ++ " and " ++ std.fmt.comptimePrint("{d}", .{i}) ++ ")");
            }
        }
    }

    return struct {
        const n_public = ic_wires.len - 1;

        /// Errors a fallible operation on this system can report.
        const Error = error{
            /// The setup's trapdoor or toxic waste is unusable.
            DegenerateSetup,
            /// The witness does not satisfy the circuit, so the QAP numerator
            /// is not divisible by the vanishing polynomial and no quotient
            /// polynomial h exists.
            QapUnsatisfied,
        };

        /// Constraint matrices, row-major: `a[g][w]` is the coefficient of
        /// wire `w` in constraint `g`.
        /// The rank-1 system, as three row-major matrices: constraint  is
        /// `a[i] . z * b[i] . z == c[i] . z`. Public because a caller cannot build
        /// one otherwise, and a reference prover nobody outside can call is not a
        /// prover.
        pub const Circuit = struct {
            a: [n_constraints][n_wires]Fr,
            b: [n_constraints][n_wires]Fr,
            c: [n_constraints][n_wires]Fr,
        };

        /// Toxic waste of the trusted setup. Never reused across circuits.
        /// The trapdoor values a ceremony produces. Public because `setup` and
        /// `prove` take one, and a caller who cannot name the type cannot call
        /// either. `isValid` is what rejects a setup that would make proofs
        /// forgeable.
        pub const Setup = struct {
            tau: Fr,
            alpha: Fr,
            beta: Fr,
            gamma: Fr,
            delta: Fr,

            /// Reject setups that would make proofs forgeable or the QAP
            /// quotient ill-defined: any zeroed value, gamma equal to delta
            /// (the public/private separator collapsing), or a trapdoor that
            /// lands inside the evaluation domain.
            pub fn isValid(s: Setup) bool {
                const parts = [_]Fr{ s.tau, s.alpha, s.beta, s.gamma, s.delta };
                for (parts) |v| {
                    if (v.isZero()) return false;
                }
                if (s.gamma.eql(s.delta)) return false;
                for (0..n_constraints) |i| {
                    if (s.tau.eql(domainPoint(i))) return false;
                }
                return true;
            }
        };

        const VerifyingKey = struct {
            alpha_g1: G1,
            beta_g2: G2,
            gamma_g2: G2,
            delta_g2: G2,
            /// `ic[0]` is the constant-one encoding, `ic[1..]` the public
            /// inputs, in the order given by `ic_wires`.
            ic: [ic_wires.len]G1,
        };

        const Proof = struct {
            a: G1,
            b: G2,
            c: G1,
        };

        /// Element `i` of the QAP evaluation domain H = {1, ..., n}.
        fn domainPoint(i: usize) Fr {
            return Fr.fromInt(i + 1);
        }

        /// Lagrange basis of H evaluated at `x`.
        ///
        /// `out[i] = prod_{j != i} (x - H_j) / (H_i - H_j)`, so
        /// `sum_i out[i] * f(H_i) == f(x)` for every `f` of degree < n.
        fn lagrange(x: Fr) [n_constraints]Fr {
            var out: [n_constraints]Fr = undefined;
            for (0..n_constraints) |i| {
                var acc = Fr.one();
                for (0..n_constraints) |j| {
                    if (j == i) continue;
                    acc = acc.mul(x.sub(domainPoint(j))).mul(domainPoint(i).sub(domainPoint(j)).inv());
                }
                out[i] = acc;
            }
            return out;
        }

        fn isKnownWire(w: usize) bool {
            for (ic_wires) |known| {
                if (known == w) return true;
            }
            return false;
        }

        /// `(beta * A_w + alpha * B_w + C_w)(tau)`: the per-wire combination
        /// the setup stores in `ic` and the prover folds into `c`.
        fn wireCombo(circuit: *const Circuit, l: [n_constraints]Fr, w: usize, s: Setup) Fr {
            var acc = Fr.zero();
            for (0..n_constraints) |g| {
                const row = s.beta.mul(circuit.a[g][w])
                    .add(s.alpha.mul(circuit.b[g][w]))
                    .add(circuit.c[g][w]);
                acc = acc.add(l[g].mul(row));
            }
            return acc;
        }

        /// `QAP(z)(tau)` for one of the three QAP polynomials: the interpolant
        /// at `tau` of the per-constraint row evaluations `(M . z)(g)`.
        fn qapEval(
            circuit: *const Circuit,
            l: [n_constraints]Fr,
            witness: [n_wires]Fr,
            comptime which: enum { a, b, c },
        ) Fr {
            var acc = Fr.zero();
            for (0..n_constraints) |g| {
                var row = Fr.zero();
                for (0..n_wires) |w| {
                    const coeff = switch (which) {
                        .a => circuit.a[g][w],
                        .b => circuit.b[g][w],
                        .c => circuit.c[g][w],
                    };
                    row = row.add(coeff.mul(witness[w]));
                }
                acc = acc.add(l[g].mul(row));
            }
            return acc;
        }

        /// True when `witness` satisfies every constraint of `circuit`.
        pub fn satisfies(circuit: *const Circuit, witness: [n_wires]Fr) bool {
            for (0..n_constraints) |g| {
                var av = Fr.zero();
                var bv = Fr.zero();
                var cv = Fr.zero();
                for (0..n_wires) |w| {
                    av = av.add(circuit.a[g][w].mul(witness[w]));
                    bv = bv.add(circuit.b[g][w].mul(witness[w]));
                    cv = cv.add(circuit.c[g][w].mul(witness[w]));
                }
                if (!av.mul(bv).eql(cv)) return false;
            }
            return true;
        }

        /// Trusted setup for one circuit: the public-input encodings plus the
        /// toxic-waste points the verifier needs.
        pub fn setup(circuit: *const Circuit, s: Setup) Error!VerifyingKey {
            if (!s.isValid()) return error.DegenerateSetup;
            const l = lagrange(s.tau);
            const gamma_inv = s.gamma.inv();

            var ic: [ic_wires.len]G1 = undefined;
            for (ic_wires, 0..) |w, i| {
                ic[i] = smG1(g1_gen, wireCombo(circuit, l, w, s).mul(gamma_inv));
            }

            return .{
                .alpha_g1 = smG1(g1_gen, s.alpha),
                .beta_g2 = smG2(g2_gen, s.beta),
                .gamma_g2 = smG2(g2_gen, s.gamma),
                .delta_g2 = smG2(g2_gen, s.delta),
                .ic = ic,
            };
        }

        /// Prove knowledge of `witness` satisfying `circuit`.
        ///
        /// `blind_r` and `blind_s` must be unpredictable to the verifier.
        ///
        /// Returns `error.QapUnsatisfied` for a witness that violates a
        /// constraint. That check is what makes `t(tau) * h(tau)` the honest
        /// quotient value: the QAP numerator vanishes on the whole evaluation
        /// domain exactly when the witness is valid, and only then is it
        /// divisible by the vanishing polynomial.
        pub fn prove(
            circuit: *const Circuit,
            witness: [n_wires]Fr,
            s: Setup,
            blind_r: Fr,
            blind_s: Fr,
        ) Error!Proof {
            if (!s.isValid()) return error.DegenerateSetup;
            if (!satisfies(circuit, witness)) return error.QapUnsatisfied;
            const l = lagrange(s.tau);

            const a_tau = qapEval(circuit, l, witness, .a);
            const b_tau = qapEval(circuit, l, witness, .b);
            const c_tau = qapEval(circuit, l, witness, .c);

            // With the QAP numerator vanishing on all of H (guaranteed by the
            // `satisfies` check above) it is divisible by the vanishing
            // polynomial t, and t(tau) * h(tau) = A(tau) * B(tau) - C(tau).
            const t_times_h = a_tau.mul(b_tau).sub(c_tau);

            // Private wires only: the known wires are accounted for by the
            // verifier through `ic`, and the constant-one wire carries no
            // witness value of its own.
            var private_sum = Fr.zero();
            for (0..n_wires) |w| {
                if (isKnownWire(w)) continue;
                private_sum = private_sum.add(witness[w].mul(wireCombo(circuit, l, w, s)));
            }

            const a_scalar = s.alpha.add(a_tau).add(blind_r.mul(s.delta));
            const b_scalar = s.beta.add(b_tau).add(blind_s.mul(s.delta));
            const c_scalar = private_sum.add(t_times_h).mul(s.delta.inv())
                .add(blind_s.mul(a_scalar))
                .add(blind_r.mul(b_scalar))
                .sub(blind_r.mul(blind_s).mul(s.delta));

            return .{
                .a = smG1(g1_gen, a_scalar),
                .b = smG2(g2_gen, b_scalar),
                .c = smG1(g1_gen, c_scalar),
            };
        }

        /// Verify `proof` against `vk` for the given public input values.
        pub fn verifyKey(vk: VerifyingKey, proof: Proof, public_inputs: [n_public]Fr) bool {
            return verify(
                vk.alpha_g1,
                vk.beta_g2,
                vk.gamma_g2,
                vk.delta_g2,
                &vk.ic,
                proof.a,
                proof.b,
                proof.c,
                &public_inputs,
            );
        }
    };
}

const testing = std.testing;

// Test circuit: 5 wires, 3 constraints, computing x^3 + x + 5 with x = 3.
//   wire 0: constant one    wire 1: x    wire 2: x^3 (public output)
//   wire 3: x^2             wire 4: x^3 / x = x * x^2
//   g0: x * x = x^2
//   g1: x^2 * x = x * x^2
//   g2: (5 + x + x * x^2) * one = x^3
// Known wires: 0 (the constant one) and 2 (the public output).
const G16 = Groth16(&.{ 0, 2 }, 3, 5);

const c_zero = Fr.zero();
const c_one = Fr.one();
const c_five = Fr.fromInt(5);

const test_circuit: G16.Circuit = .{
    .a = .{
        .{ c_zero, c_one, c_zero, c_zero, c_zero },
        .{ c_zero, c_zero, c_zero, c_one, c_zero },
        .{ c_five, c_one, c_zero, c_zero, c_one },
    },
    .b = .{
        .{ c_zero, c_one, c_zero, c_zero, c_zero },
        .{ c_zero, c_one, c_zero, c_zero, c_zero },
        .{ c_one, c_zero, c_zero, c_zero, c_zero },
    },
    .c = .{
        .{ c_zero, c_zero, c_zero, c_one, c_zero },
        .{ c_zero, c_zero, c_zero, c_zero, c_one },
        .{ c_zero, c_zero, c_one, c_zero, c_zero },
    },
};

const setup: G16.Setup = .{
    .tau = Fr.fromInt(42),
    .alpha = Fr.fromInt(11111),
    .beta = Fr.fromInt(22222),
    .gamma = Fr.fromInt(44444),
    .delta = Fr.fromInt(33333),
};

/// x = 3, so x^2 = 9, x * x^2 = 27 and x^3 = 35.
const test_witness: [5]Fr = .{
    Fr.one(),
    Fr.fromInt(3),
    Fr.fromInt(35),
    Fr.fromInt(9),
    Fr.fromInt(27),
};

const test_blind_r = Fr.fromInt(7);
const test_blind_s = Fr.fromInt(11);

test "groth16: setup and witness sanity" {
    try testing.expect(setup.isValid());
    try testing.expect(G16.satisfies(&test_circuit, test_witness));

    // A wrong output must be caught by the constraint check itself.
    var broken = test_witness;
    broken[2] = Fr.fromInt(34);
    try testing.expect(!G16.satisfies(&test_circuit, broken));

    try testing.expect(g1_gen.isOnCurve());
    try testing.expect(g2_gen.isOnCurve());

    // Scalar multiplication agrees with repeated addition.
    for ([_]Fr{ Fr.one(), Fr.fromInt(2), Fr.fromInt(5), Fr.fromInt(37) }) |s| {
        var iterated = G1.zero();
        var i: usize = 0;
        while (i < s.toU64()) : (i += 1) iterated = iterated.add(g1_gen);
        try testing.expect(smG1(g1_gen, s).eql(iterated));
    }
    try testing.expect(smG1(g1_gen, Fr.zero()).infinity);
}

test "groth16: full roundtrip" {
    const vk = try G16.setup(&test_circuit, setup);
    const proof = try G16.prove(&test_circuit, test_witness, setup, test_blind_r, test_blind_s);

    try testing.expect(proof.a.isOnCurve());
    try testing.expect(proof.b.isOnCurve());
    try testing.expect(proof.c.isOnCurve());

    try testing.expect(G16.verifyKey(vk, proof, .{Fr.fromInt(35)}));
}

test "groth16: rejects wrong public input" {
    const vk = try G16.setup(&test_circuit, setup);
    const proof = try G16.prove(&test_circuit, test_witness, setup, test_blind_r, test_blind_s);

    try testing.expect(!G16.verifyKey(vk, proof, .{Fr.fromInt(36)}));
    try testing.expect(!G16.verifyKey(vk, proof, .{Fr.zero()}));
}

test "groth16: rejects tampered proof" {
    const vk = try G16.setup(&test_circuit, setup);
    const proof = try G16.prove(&test_circuit, test_witness, setup, test_blind_r, test_blind_s);

    var bad_a = proof;
    bad_a.a = bad_a.a.add(g1_gen);
    try testing.expect(!G16.verifyKey(vk, bad_a, .{Fr.fromInt(35)}));

    var bad_b = proof;
    bad_b.b = bad_b.b.add(g2_gen);
    try testing.expect(!G16.verifyKey(vk, bad_b, .{Fr.fromInt(35)}));

    var bad_c = proof;
    bad_c.c = bad_c.c.add(g1_gen);
    try testing.expect(!G16.verifyKey(vk, bad_c, .{Fr.fromInt(35)}));
}

test "groth16: refuses to prove an unsatisfied witness" {
    // The output wire claims 34 instead of 35, so constraint g2 fails and the
    // QAP numerator no longer vanishes on H: there is no quotient h, so the
    // prover must refuse instead of emitting a proof.
    var bad = test_witness;
    bad[2] = Fr.fromInt(34);
    try testing.expect(!G16.satisfies(&test_circuit, bad));
    try testing.expectError(
        error.QapUnsatisfied,
        G16.prove(&test_circuit, bad, setup, test_blind_r, test_blind_s),
    );
}

test "groth16: refuses a degenerate setup" {
    // gamma == delta collapses the public/private separator.
    var collapsed = setup;
    collapsed.delta = collapsed.gamma;
    try testing.expect(!collapsed.isValid());
    try testing.expectError(
        error.DegenerateSetup,
        G16.setup(&test_circuit, collapsed),
    );
    try testing.expectError(
        error.DegenerateSetup,
        G16.prove(&test_circuit, test_witness, collapsed, test_blind_r, test_blind_s),
    );

    // A trapdoor inside the evaluation domain makes t(tau) zero.
    var in_domain = setup;
    in_domain.tau = Fr.fromInt(2);
    try testing.expect(!in_domain.isValid());
    try testing.expectError(
        error.DegenerateSetup,
        G16.setup(&test_circuit, in_domain),
    );

    // Zeroed toxic waste is unusable.
    var zeroed = setup;
    zeroed.alpha = Fr.zero();
    try testing.expectError(
        error.DegenerateSetup,
        G16.setup(&test_circuit, zeroed),
    );
}

test "groth16: rejects proof under a different setup" {
    const vk = try G16.setup(&test_circuit, setup);

    var other = setup;
    other.tau = Fr.fromInt(43);
    const other_vk = try G16.setup(&test_circuit, other);
    const proof = try G16.prove(&test_circuit, test_witness, other, test_blind_r, test_blind_s);

    try testing.expect(G16.verifyKey(other_vk, proof, .{Fr.fromInt(35)}));
    try testing.expect(!G16.verifyKey(vk, proof, .{Fr.fromInt(35)}));
}

test "groth16: blinding factors do not change acceptance" {
    const vk = try G16.setup(&test_circuit, setup);

    const p0 = try G16.prove(&test_circuit, test_witness, setup, Fr.zero(), Fr.zero());
    const p1 = try G16.prove(&test_circuit, test_witness, setup, Fr.one(), Fr.fromInt(12345));

    try testing.expect(G16.verifyKey(vk, p0, .{Fr.fromInt(35)}));
    try testing.expect(G16.verifyKey(vk, p1, .{Fr.fromInt(35)}));
    try testing.expect(!p0.a.eql(p1.a));
    try testing.expect(!p0.b.eql(p1.b));
    try testing.expect(!p0.c.eql(p1.c));
}

test "groth16: verify rejects malformed public input arity" {
    const vk = try G16.setup(&test_circuit, setup);
    const proof = try G16.prove(&test_circuit, test_witness, setup, test_blind_r, test_blind_s);

    // `ic` holds the one-wire plus one public input; anything else is bogus.
    try testing.expect(!verify(
        vk.alpha_g1,
        vk.beta_g2,
        vk.gamma_g2,
        vk.delta_g2,
        vk.ic[0..1],
        proof.a,
        proof.b,
        proof.c,
        &.{Fr.fromInt(35)},
    ));
    try testing.expect(!verify(
        vk.alpha_g1,
        vk.beta_g2,
        vk.gamma_g2,
        vk.delta_g2,
        vk.ic[0..],
        proof.a,
        proof.b,
        proof.c,
        &.{},
    ));
    try testing.expect(!verify(
        vk.alpha_g1,
        vk.beta_g2,
        vk.gamma_g2,
        vk.delta_g2,
        vk.ic[0..],
        proof.a,
        proof.b,
        proof.c,
        &.{ Fr.fromInt(35), Fr.fromInt(1) },
    ));
}

test "groth16: rejects off-curve proof elements" {
    const vk = try G16.setup(&test_circuit, setup);
    const proof = try G16.prove(&test_circuit, test_witness, setup, test_blind_r, test_blind_s);
    try testing.expect(G16.verifyKey(vk, proof, .{Fr.fromInt(35)}));

    // (1, 1) is not on BN254's G1, and (1 + u, 1 + u) is not on its G2. The
    // pairing would map both to the identity; the verifier must not let a
    // bogus element quietly cancel a term of the equation.
    const bogus_g1: G1 = .{
        .x = Fp.one(),
        .y = Fp.one(),
        .infinity = false,
    };
    try testing.expect(!bogus_g1.isOnCurve());

    const bogus_f2 = Fp2.new(Fp.one(), Fp.one());
    const bogus_g2: G2 = .{
        .x = bogus_f2,
        .y = bogus_f2,
        .infinity = false,
    };
    try testing.expect(!bogus_g2.isOnCurve());

    var bad_a = proof;
    bad_a.a = bogus_g1;
    try testing.expect(!G16.verifyKey(vk, bad_a, .{Fr.fromInt(35)}));

    var bad_b = proof;
    bad_b.b = bogus_g2;
    try testing.expect(!G16.verifyKey(vk, bad_b, .{Fr.fromInt(35)}));

    var bad_c = proof;
    bad_c.c = bogus_g1;
    try testing.expect(!G16.verifyKey(vk, bad_c, .{Fr.fromInt(35)}));
}

test "pairing: bilinearity on the BN254 tower" {
    const gt = tp.pairing(g1_gen, g2_gen);
    const a = Fr.fromInt(31337);
    const b = Fr.fromInt(65537);

    const lhs = tp.pairing(smG1(g1_gen, a), smG2(g2_gen, b));
    try testing.expect(lhs.eql(gt.powFast(a.mul(b).toU512())));

    // Additive structure is respected too.
    const sum = smG1(g1_gen, a.add(b));
    try testing.expect(tp.pairing(sum, g2_gen).eql(gt.powFast(a.add(b).toU512())));
}

// --- interoperability with snarkjs -----------------------------------------
//
// The vectors in `vectors/` are produced by snarkjs 0.7.6, not by anything in
// this repository, and `vectors/regenerate.mjs` is the recipe. They are
// embedded rather than read at runtime: a test that resolves a path at runtime
// depends on the working directory, and a fixture that cannot be found is a
// failure that looks like a pass when the step is skipped.
//
// snarkjs writes G1 as [x, y, z] and G2 as [[x1, x2], [y1, y2], [z1, z2]] in
// projective form. Both are z == 1 here, but the parsers divide by z instead of
// assuming it, because an assumption that happens to hold on the committed file
// is exactly the kind of thing that breaks on someone else's proof.
const Fp = zc.bn254.Fp;
const Fp2 = zc.bn254.Fp2;

/// A decimal string as snarkjs writes field elements: no exponent, no sign.
fn fieldFromJson(comptime T: type, s: []const u8) !T {
    return T.fromInt(std.fmt.parseInt(u512, s, 10) catch return error.BadVector);
}

fn g1FromJson(v: std.json.Value) !G1 {
    const xs = v.array;
    if (xs.items.len != 3) return error.BadVector;
    const x = try fieldFromJson(Fp, xs.items[0].string);
    const y = try fieldFromJson(Fp, xs.items[1].string);
    const z = try fieldFromJson(Fp, xs.items[2].string);
    if (z.isZero()) return error.BadVector;
    // Projective to affine. snarkjs emits z == 1, so this is a division by one
    // for the committed vectors; the code is here so a z != 1 vector from
    // another producer is read correctly rather than silently misread.
    const zi = z.inv();
    return .{ .x = x.mul(zi), .y = y.mul(zi), .infinity = false };
}

fn g2FromJson(v: std.json.Value) !G2 {
    const cs = v.array;
    if (cs.items.len != 3) return error.BadVector;
    var coord: [2]Fp = undefined;
    for (cs.items[0].array.items, 0..) |c, i| {
        if (i >= 2) return error.BadVector;
        coord[i] = try fieldFromJson(Fp, c.string);
    }
    const x = Fp2.new(coord[0], coord[1]);
    var yc: [2]Fp = undefined;
    for (cs.items[1].array.items, 0..) |c, i| {
        if (i >= 2) return error.BadVector;
        yc[i] = try fieldFromJson(Fp, c.string);
    }
    const y = Fp2.new(yc[0], yc[1]);
    var zc_: [2]Fp = undefined;
    for (cs.items[2].array.items, 0..) |c, i| {
        if (i >= 2) return error.BadVector;
        zc_[i] = try fieldFromJson(Fp, c.string);
    }
    const z = Fp2.new(zc_[0], zc_[1]);
    if (z.isZero()) return error.BadVector;
    const zi = z.inv();
    return .{ .x = x.mul(zi), .y = y.mul(zi), .infinity = false };
}

const SnarkjsVec = struct {
    alpha1: G1,
    beta2: G2,
    gamma2: G2,
    delta2: G2,
    ic: []G1,
    a: G1,
    b: G2,
    c: G1,
    public: []Fr,
};

fn loadSnarkjsVector(alloc: std.mem.Allocator) !SnarkjsVec {
    const vk_text = @embedFile("vectors/vk.json");
    const pr_text = @embedFile("vectors/proof.json");
    const pub_text = @embedFile("vectors/public.json");

    const vk = try std.json.parseFromSlice(std.json.Value, alloc, vk_text, .{});
    defer vk.deinit();
    const pr = try std.json.parseFromSlice(std.json.Value, alloc, pr_text, .{});
    defer pr.deinit();
    const pub_v = try std.json.parseFromSlice(std.json.Value, alloc, pub_text, .{});
    defer pub_v.deinit();

    const o = vk.value.object;
    const ic_json = o.get("IC").?.array;
    const ic = try alloc.alloc(G1, ic_json.items.len);
    for (ic_json.items, ic) |item, *slot| slot.* = try g1FromJson(item);

    const public = try alloc.alloc(Fr, pub_v.value.array.items.len);
    for (pub_v.value.array.items, public) |item, *slot| {
        slot.* = try fieldFromJson(Fr, item.string);
    }

    return .{
        .alpha1 = try g1FromJson(o.get("vk_alpha_1").?),
        .beta2 = try g2FromJson(o.get("vk_beta_2").?),
        .gamma2 = try g2FromJson(o.get("vk_gamma_2").?),
        .delta2 = try g2FromJson(o.get("vk_delta_2").?),
        .ic = ic,
        .a = try g1FromJson(pr.value.object.get("pi_a").?),
        .b = try g2FromJson(pr.value.object.get("pi_b").?),
        .c = try g1FromJson(pr.value.object.get("pi_c").?),
        .public = public,
    };
}

test "groth16: verifies a proof produced by snarkjs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const v = try loadSnarkjsVector(arena.allocator());

    // The circuit is c = a * b with c the one public signal, so `IC` holds the
    // constant-one wire plus that single input.
    try testing.expectEqual(@as(usize, 2), v.ic.len);
    try testing.expectEqual(@as(usize, 1), v.public.len);
    try testing.expectEqual(Fr.fromInt(21), v.public[0]);

    try testing.expect(verify(
        v.alpha1,
        v.beta2,
        v.gamma2,
        v.delta2,
        v.ic,
        v.a,
        v.b,
        v.c,
        v.public,
    ));
}

test "groth16: the snarkjs vector is only accepted for its own public input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const v = try loadSnarkjsVector(arena.allocator());

    // Without this, the test above could be passing because the verifier
    // returns true for anything, which is a different bug with the same
    // green build.
    try testing.expect(!verify(
        v.alpha1,
        v.beta2,
        v.gamma2,
        v.delta2,
        v.ic,
        v.a,
        v.b,
        v.c,
        &.{Fr.fromInt(22)},
    ));
}
