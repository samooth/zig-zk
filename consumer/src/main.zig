//! A consumer of zig-zk, through the public API and nothing else.
//!
//! It is an executable rather than a test, because that is what a stranger
//! builds. Every test in the library lives inside the module it tests, where a
//! `const` is visible to the test and invisible to everyone else, so a suite of
//! 254 green tests said nothing about whether a caller outside could reach any
//! of this. Five things were broken for a consumer and invisible to the suite;
//! this file is what makes that impossible to keep.
//!
//! Nothing here is a benchmark and nothing here is fast. Each section does the
//! smallest honest thing with one library, so that a failure names the library.

const std = @import("std");
const M31 = @import("zig-stark").m31.M31;
const commitment = @import("zig-commitment");
const signature = @import("zig-signature");
const snark = @import("zig-snark");
const stark = @import("zig-stark");
const transcript = @import("zig-transcript");

var failures: usize = 0;

fn check(ok: bool, comptime what: []const u8) void {
    if (ok) {
        std.debug.print("  ok    {s}\n", .{what});
    } else {
        failures += 1;
        std.debug.print("  FALLA {s}\n", .{what});
    }
}

/// The 128-bit tower the Binius stack is meant to run on, named by the caller.
const F = stark.binius.tower.Gf16;
const E = stark.binius.tower.Gf2_128;

// --- transcript -------------------------------------------------------------

/// Two channels, one label. The same label has to give the same challenge and a
/// different label a different one, which is what makes a transcript binding.
fn useTranscript() !void {
    var a = transcript.Channel.init("consumer-demo");
    var b = transcript.Channel.init("consumer-demo");
    var c = transcript.Channel.init("otro-dominio");

    a.absorbBytes("mensaje");
    b.absorbBytes("mensaje");
    c.absorbBytes("mensaje");

    const ca = a.sample(M31);
    const cb = b.sample(M31);
    const cc = c.sample(M31);

    check(ca.eq(cb), "transcript: mismo dominio y mensaje, mismo reto");
    check(!ca.eq(cc), "transcript: dominio distinto, reto distinto");

    // A field challenge. Two channels with the same label and the same
    // message, because a channel is stateful: sampling it twice gives two
    // different values, which is the point, not a bug.
    var d = transcript.Channel.init("campo");
    var e = transcript.Channel.init("campo");
    d.absorbBytes("x");
    e.absorbBytes("x");
    const f1 = d.sample(M31);
    const f2 = e.sample(M31);
    check(f1.eq(f2), "transcript: squeeze de un campo de 31 bits con dos canales iguales");

    // squeezeField on a real field. It used to read `F.order`, which no field in
    // this repository or in the pin declares, so it compiled only against the
    // test-local scalars -- which had invented one.
    var g = transcript.Transcript.init("campo");
    g.absorbField(M31, M31.fromInt(99));
    const squeezed = g.squeezeField(M31);
    check(squeezed.eq(M31.fromInt(@intCast(squeezed.toInt()))), "transcript: squeezeField con M31");

    // And the statefulness itself, so the reason the quick start fails is
    // written down rather than rediscovered.
    const f3 = d.sample(M31);
    check(!f1.eq(f3), "transcript: el canal avanza al muestrear");
}

// --- commitment -------------------------------------------------------------

/// Split a secret into shares over a real field, and recombine them.
fn useCommitment(alloc: std.mem.Allocator) !void {
    var prng = std.Random.DefaultPrng.init(0xc0ffee);
    const rnd = prng.random();
    const t0 = M31.fromInt(11);

    const shares = commitment.shamir.split(M31, t0, 3, 3, alloc, rnd) catch |err| {
        failures += 1;
        std.debug.print("  FALLA commitment: shamir.split no compila con M31: {t}\n", .{err});
        return;
    };
    check(shares.len == 3, "commitment: shamir devuelve el numero de partes pedido");

    // Three shares, because the threshold is three: a degree-2 polynomial
    // needs three points, and two of them reconstruct a different secret.
    const three = [_]commitment.shamir.Share(M31){ shares[0], shares[1], shares[2] };
    const recovered = commitment.shamir.reconstruct(M31, &three) catch |err| {
        failures += 1;
        std.debug.print("  FALLA commitment: reconstruct: {t}\n", .{err});
        return;
    };
    check(recovered.eq(t0), "commitment: shamir con un campo real (M31)");

    // Two shares are below the threshold and give a different secret, not an
    // error. That difference is the whole security property.
    const two = [_]commitment.shamir.Share(M31){ shares[0], shares[1] };
    const under = commitment.shamir.reconstruct(M31, &two) catch unreachable;
    check(!under.eq(t0), "commitment: por debajo del umbral no se recupera");
}

// --- signature --------------------------------------------------------------

/// Sign a message and verify it.
fn useSignature(io: std.Io) !void {
    var seed: [signature.ed25519.seed_length]u8 = undefined;
    io.random(&seed);
    const kp = try signature.ed25519.keyPairFromSeed(seed);

    const msg = "un mensaje para el consumidor";
    const sig = try signature.ed25519.sign(msg, kp, null);
    check(signature.ed25519.verify(sig, msg, kp.public_key), "signature: Ed25519 valida");
    check(signature.ed25519.verifyStrict(sig, msg, kp.public_key), "signature: Ed25519 estricta valida");

    // A different message must not verify, and a flipped bit must not either.
    const otro = "un mensaje para el consumidor.";
    check(!signature.ed25519.verify(sig, otro, kp.public_key), "signature: otro mensaje no valida");

    var bad = sig;
    bad.r[0] ^= 0x01;
    check(!signature.ed25519.verify(bad, msg, kp.public_key), "signature: un bit cambiado no valida");
}

// --- snark ------------------------------------------------------------------

/// Prove and verify a rank-1 constraint system through the public API.
fn useSnark() !void {
    // Groth16 over 4 wires and 1 constraint: c = a * b, c the public signal.
    const G16 = snark.Groth16(&.{ 0, 1 }, 1, 4);
    const Fr = snark.Fr;

    const z = Fr.zero();
    const o = Fr.one();
    const circuit: G16.Circuit = .{
        .a = .{.{ z, z, o, z }},
        .b = .{.{ z, z, z, o }},
        .c = .{.{ z, o, z, z }},
    };
    const witness = [4]Fr{ o, Fr.fromInt(21), Fr.fromInt(3), Fr.fromInt(7) };
    check(G16.satisfies(&circuit, witness), "snark: el testigo satisface el sistema");

    const setup: G16.Setup = .{
        .tau = Fr.fromInt(42),
        .alpha = Fr.fromInt(11111),
        .beta = Fr.fromInt(22222),
        .gamma = Fr.fromInt(44444),
        .delta = Fr.fromInt(33333),
    };
    const vk = try G16.setup(&circuit, setup);
    const proof = try G16.prove(&circuit, witness, setup, Fr.fromInt(7), Fr.fromInt(11));
    check(G16.verifyKey(vk, proof, .{Fr.fromInt(21)}), "snark: prueba Groth16 valida");

    // A public input that is not the one proven.
    check(!G16.verifyKey(vk, proof, .{Fr.fromInt(22)}), "snark: otra senal publica no valida");

    // And the free function a consumer would reach for first.
    check(snark.verify(
        vk.alpha_g1,
        vk.beta_g2,
        vk.gamma_g2,
        vk.delta_g2,
        &vk.ic,
        proof.a,
        proof.b,
        proof.c,
        &[_]Fr{Fr.fromInt(21)},
    ), "snark: verify() acepta la misma prueba");
}

// --- stark ------------------------------------------------------------------

/// Prove and verify a Binius statement, and count the sum-check rounds.
fn useStark(alloc: std.mem.Allocator) !void {
    const Adder = stark.binius.adder.Adder(F, E);
    const Stark = stark.binius.stark.BiniusStark(F, E);

    const k: usize = 3;
    const n = @as(usize, 1) << @intCast(k);
    const x = try alloc.alloc(u4, n);
    defer alloc.free(x);
    const y = try alloc.alloc(u4, n);
    defer alloc.free(y);
    for (0..n) |i| {
        x[i] = @intCast((i * 3 + 5) % 16);
        y[i] = @intCast((i * 7 + 2) % 16);
    }

    const columns = try Adder.generateWitness(alloc, x, y);
    defer Adder.freeWitness(alloc, &columns);

    var proof = try Stark.prove(alloc, k, columns[0..], Adder.constraints[0..], &.{}, "consumer");
    defer proof.deinit(alloc);
    check(proof.sumcheck.rounds.len == k, "stark: las rondas del sum-check igualan k");

    // Commitments, then verify against those roots.
    var roots: [Adder.num_columns]stark.hash.Hash.Digest = undefined;
    const Pcs = stark.binius.pcs.CommittedMlePcs(F, E);
    for (columns[0..], 0..) |col, j| {
        var tree = try Pcs.commit(alloc, col);
        defer tree.deinit();
        roots[j] = tree.root();
    }
    const ok = try Stark.verify(
        alloc,
        k,
        &roots,
        Adder.constraints[0..],
        &.{},
        proof,
        "consumer",
    );
    check(ok, "stark: prueba Binius valida sobre una extension de 128 bits");

    // A transcript channel per side, with the same label. Reusing one channel
    // for both is what made the quick start verify as false with no error.
    var prover_ch = stark.channel.Channel.init("consumer");
    var verifier_ch = stark.channel.Channel.init("consumer");
    prover_ch.absorbBytes("consumer");
    verifier_ch.absorbBytes("consumer");
    const c1 = prover_ch.sample(M31);
    const c2 = verifier_ch.sample(M31);
    check(c1.eq(c2), "stark: dos canales con la misma etiqueta convienen");
}

/// The M31 STARK, written as `libs/stark/README.md` writes it.
///
/// Kept verbatim on purpose. The quick start creates one channel and passes it
/// to `prove` and then to `verify`, which makes verification return `false`
/// with no error -- the worst shape a failure can have in an example, because
/// the reader does not get an exception, does not get a red build, and spends a
/// day looking for the reason. The library's own tests use two channels with
/// one label, which is the tell that nobody ran the example.
fn useStarkFib(alloc: std.mem.Allocator) !void {
    // El README dice `zs.m31.stark`, pero `zs.m31` es el campo, no un
    // namespace. El nombre real es `zs.stark`.
    const m31 = stark.stark;
    const Stark = m31.GenericStark(m31.FibAir);
    const params = m31.StarkParams{ .trace_log = 8 };
    var channel = stark.channel.Channel.init("mi-prueba");

    const trace = try m31.FibAir.generateTrace(alloc, params.traceLen());
    defer m31.FibAir.freeTrace(alloc, trace);

    // `claimed_fib` es el ultimo valor de la columna 0, no un numero cualquiera:
    // reclamar otra cosa es una prueba de una afirmacion distinta.
    // `trace.len` es el numero de columnas, no de pasos.
    const claimed = trace[0][params.traceLen() - 1];
    var proof = try Stark.prove(alloc, params, .{ .claimed_fib = claimed }, trace, &channel);
    defer proof.deinit();

    // The README's next line, unchanged. It returns false and raises nothing:
    // a channel is stateful, `prove` moved it, and `verify` samples a different
    // challenge. Recorded here rather than asserted, because the README no
    // longer says this. The shape of the failure is the part worth keeping --
    // a consumer who writes it sees a rejected proof, not an error.
    const como_esta = try Stark.verify(alloc, params, .{ .claimed_fib = claimed }, &proof, &channel);
    check(!como_esta, "stark: el ejemplo del README devolvia false sin error alguno");

    // The way it should be written: a second channel with the same label.
    var otro = stark.channel.Channel.init("mi-prueba");
    const como_debe = try Stark.verify(alloc, params, .{ .claimed_fib = claimed }, &proof, &otro);
    check(como_debe, "stark: el mismo ejemplo con dos canales y una etiqueta");

    // And the way the mistake becomes recoverable.
    channel.reset("mi-prueba");
    const tras_reset = try Stark.verify(alloc, params, .{ .claimed_fib = claimed }, &proof, &channel);
    check(tras_reset, "stark: reset devuelve el canal al estado inicial");

    // Y con el tamano de traza que usa la prueba de la libreria.
    const p4 = m31.StarkParams{ .trace_log = 4, .log_blowup = 3, .num_queries = 12 };
    const t4 = try m31.FibAir.generateTrace(alloc, p4.traceLen());
    defer m31.FibAir.freeTrace(alloc, t4);
    var pc4 = stark.channel.Channel.init("fib-4");
    var pr4 = try Stark.prove(alloc, p4, .{ .claimed_fib = t4[0][p4.traceLen() - 1] }, t4, &pc4);
    defer pr4.deinit();
    var vc4 = stark.channel.Channel.init("fib-4");
    check(try Stark.verify(alloc, p4, .{ .claimed_fib = t4[0][p4.traceLen() - 1] }, &pr4, &vc4), "stark: el mismo circuito con trace_log=4");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    std.debug.print("zig-zk como consumidor externo\n", .{});

    std.debug.print("transcript\n", .{});
    try useTranscript();

    std.debug.print("commitment\n", .{});
    try useCommitment(alloc);

    std.debug.print("signature\n", .{});
    try useSignature(io);

    std.debug.print("snark\n", .{});
    try useSnark();

    std.debug.print("stark\n", .{});
    try useStark(alloc);
    try useStarkFib(alloc);

    if (failures == 0) {
        std.debug.print("\nlas cinco librerias son usables desde fuera\n", .{});
    } else {
        std.debug.print("\n{d} comprobaciones fallan\n", .{failures});
        return error.ConsumerCheckFailed;
    }
}
