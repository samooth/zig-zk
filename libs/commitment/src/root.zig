//! zig-commitment: Commitment schemes over finite fields.
//!
//! Provides:
//! - IPA (Inner Product Argument) - Bulletproofs-style logarithmic proof of `<a, b> = c`
//! - Pedersen commitment - additively homomorphic commitment scheme
//! - Shamir Secret Sharing - threshold secret sharing with Lagrange interpolation
//! - Sigma protocols - Schnorr PoK and CDS '94 OR proof
//! - Future: KZG, FRI, etc.

const std = @import("std");
const traits = @import("zig-algebra-traits");
const zf = @import("zig-field");
const merkle = @import("zig-merkle");
const poly = @import("zig-poly");

pub const pedersen = @import("pedersen.zig");
pub const shamir = @import("shamir.zig");
pub const sigma = @import("sigma.zig");

/// Bulletproofs-style inner product argument, generic over a finite field.
///
/// Proves knowledge of vectors a, b with `<a, b> = c` relative to a
/// commitment `C = sum a_i g_i + sum b_i h_i + c u`, in log(n) rounds.
pub fn Ipa(comptime F: type) type {
    return struct {
        const Self = @This();

        /// Running Fiat-Shamir sponge (Blake3). Every absorbed value feeds
        /// forward, so each derived challenge binds the full statement
        /// (generators, commitment) and all prior round values.
        const Fs = struct {
            const Sponge = std.crypto.hash.Blake3;

            hasher: Sponge,

            fn init() Fs {
                var h = Sponge.init(.{});
                h.update("zig-commitment:Ipa:v1");
                return .{ .hasher = h };
            }

            fn absorbBytes(self: *Fs, bytes: []const u8) void {
                var len_buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &len_buf, bytes.len, .little);
                self.hasher.update(&len_buf);
                self.hasher.update(bytes);
            }

            fn absorbField(self: *Fs, f: F) void {
                const enc = f.toBytes();
                self.absorbBytes(&enc);
            }

            fn absorbU64(self: *Fs, v: u64) void {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &buf, v, .little);
                self.absorbBytes(&buf);
            }

            /// Derive a uniform field element from the current sponge state.
            /// Rejection-samples on the canonical encoding (< modulus); the
            /// rejected digest is absorbed so every iteration advances state.
            fn challenge(self: *Fs) F {
                while (true) {
                    var out: [32]u8 = undefined;
                    var peek = self.hasher;
                    peek.final(&out);
                    self.absorbBytes(&out);
                    const v = F.fromBytes(out[0..F.NUM_BYTES]) catch continue;
                    return v;
                }
            }
        };

        /// Bind the statement (size, generators, blinding base and commitment)
        /// into the transcript. Prover and verifier must call this in the same
        /// order before deriving any round challenge.
        fn bindStatement(fs: *Fs, self: Self, commitment: F) void {
            fs.absorbU64(self.n);
            for (self.g) |gi| fs.absorbField(gi);
            for (self.h) |hi| fs.absorbField(hi);
            fs.absorbField(self.u);
            fs.absorbField(commitment);
        }

        allocator: std.mem.Allocator,
        n: usize,
        g: []F,
        h: []F,
        u: F,

        pub fn init(allocator: std.mem.Allocator, n: usize, seed: [32]u8) !Self {
            if (n == 0 or (n & (n - 1)) != 0) return error.LengthNotPowerOfTwo;

            const g = try allocator.alloc(F, n);
            errdefer allocator.free(g);
            const h = try allocator.alloc(F, n);
            errdefer allocator.free(h);

            var prng = std.Random.DefaultPrng.init(std.mem.readInt(u64, seed[0..8], .little));
            const rnd = prng.random();

            for (0..n) |i| {
                g[i] = F.random(rnd);
                h[i] = F.random(rnd);
            }
            const u = F.random(rnd);

            return .{
                .allocator = allocator,
                .n = n,
                .g = g,
                .h = h,
                .u = u,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.g);
            self.allocator.free(self.h);
        }

        /// `error.LengthMismatch` when the vectors differ in length. Zipping
        /// two different lengths would silently drop the tail of the longer one.
        pub fn innerProduct(a: []const F, b: []const F) error{LengthMismatch}!F {
            if (a.len != b.len) return error.LengthMismatch;
            var result = F.zero();
            for (a, b) |ai, bi| {
                result = result.add(ai.mul(bi));
            }
            return result;
        }

        /// Pedersen-style vector commitment binding a, b and the inner product c.
        /// `error.LengthMismatch` unless both vectors have exactly `n` entries.
        pub fn commit(self: Self, a: []const F, b: []const F, c: F) error{LengthMismatch}!F {
            if (a.len != self.n or b.len != self.n) return error.LengthMismatch;
            var result = F.zero();
            for (a, self.g) |ai, gi| result = result.add(ai.mul(gi));
            for (b, self.h) |bi, hi| result = result.add(bi.mul(hi));
            result = result.add(c.mul(self.u));
            return result;
        }

        pub const Proof = struct {
            l: []F,
            r: []F,
            a0: F,
            b0: F,

            pub fn deinit(self: *const Proof, allocator: std.mem.Allocator) void {
                allocator.free(self.l);
                allocator.free(self.r);
            }
        };

        pub fn prove(
            self: Self,
            allocator: std.mem.Allocator,
            a_in: []const F,
            b_in: []const F,
        ) !Proof {
            if (a_in.len != self.n or b_in.len != self.n) return error.LengthMismatch;
            const log_n = @ctz(self.n);

            const a = try allocator.alloc(F, self.n);
            defer allocator.free(a);
            @memcpy(a, a_in);

            const b = try allocator.alloc(F, self.n);
            defer allocator.free(b);
            @memcpy(b, b_in);

            const g = try allocator.alloc(F, self.n);
            defer allocator.free(g);
            @memcpy(g, self.g);

            const h = try allocator.alloc(F, self.n);
            defer allocator.free(h);
            @memcpy(h, self.h);

            const l = try allocator.alloc(F, log_n);
            errdefer allocator.free(l);
            const r = try allocator.alloc(F, log_n);
            errdefer allocator.free(r);

            // Bind the statement to the Fiat-Shamir transcript before any
            // challenge is derived.
            var fs = Fs.init();
            bindStatement(&fs, self, try self.commit(a, b, try innerProduct(a, b)));

            var n = self.n;
            var round: usize = 0;
            while (n > 1) {
                const half = n / 2;

                var l_commit = F.zero();
                for (a[0..half], g[half..n]) |ai, gi| l_commit = l_commit.add(ai.mul(gi));
                for (b[half..n], h[0..half]) |bi, hi| l_commit = l_commit.add(bi.mul(hi));
                var l_ip = F.zero();
                for (a[0..half], b[half..n]) |ai, bi| l_ip = l_ip.add(ai.mul(bi));
                l_commit = l_commit.add(l_ip.mul(self.u));
                l[round] = l_commit;

                var r_commit = F.zero();
                for (a[half..n], g[0..half]) |ai, gi| r_commit = r_commit.add(ai.mul(gi));
                for (b[0..half], h[half..n]) |bi, hi| r_commit = r_commit.add(bi.mul(hi));
                var r_ip = F.zero();
                for (a[half..n], b[0..half]) |ai, bi| r_ip = r_ip.add(ai.mul(bi));
                r_commit = r_commit.add(r_ip.mul(self.u));
                r[round] = r_commit;

                fs.absorbField(l[round]);
                fs.absorbField(r[round]);
                const x = fs.challenge();
                const x_inv = x.inv();

                for (0..half) |i| {
                    a[i] = a[i].mul(x).add(a[half + i].mul(x_inv));
                    b[i] = b[i].mul(x_inv).add(b[half + i].mul(x));
                    g[i] = g[i].mul(x_inv).add(g[half + i].mul(x));
                    h[i] = h[i].mul(x).add(h[half + i].mul(x_inv));
                }

                n = half;
                round += 1;
            }

            return .{
                .l = l,
                .r = r,
                .a0 = a[0],
                .b0 = b[0],
            };
        }

        /// Verify a proof against the full vector commitment.
        ///
        /// Checks the folded identity
        ///   C - sum_j x_j^2 L_j - sum_j x_j^-2 R_j
        ///     == a0 g' + b0 h' + a0 b0 u.
        ///
        /// Note: verification requires the commitment C; the inner product
        /// value alone does not determine a unique committed vector pair.
        pub fn verify(
            self: Self,
            commitment: F,
            proof: *const Proof,
        ) !void {
            if (proof.l.len != proof.r.len) return error.MalformedProof;
            const log_n = proof.l.len;
            if (self.n != (@as(usize, 1) << @intCast(log_n))) return error.VerificationFailed;

            // Replay the prover's transcript to rederive the round challenges.
            var fs = Fs.init();
            bindStatement(&fs, self, commitment);
            const challenges = try self.allocator.alloc(F, log_n);
            defer self.allocator.free(challenges);
            for (proof.l, proof.r, 0..) |lj, rj, j| {
                fs.absorbField(lj);
                fs.absorbField(rj);
                challenges[j] = fs.challenge();
            }

            const s = try self.generatorScalars(challenges);
            defer self.allocator.free(s);

            var g_final = F.zero();
            var h_final = F.zero();
            for (0..self.n) |i| {
                g_final = g_final.add(self.g[i].mul(s[i]));
                h_final = h_final.add(self.h[i].mul(s[i].inv()));
            }

            var rhs = proof.a0.mul(g_final)
                .add(proof.b0.mul(h_final))
                .add(proof.a0.mul(proof.b0).mul(self.u));

            // Unrolling C_{k+1} = C_k + x_k^2 L_k + x_k^-2 R_k down to
            // C_final = a0 g' + b0 h' + a0 b0 u gives
            //   C = a0 g' + b0 h' + a0 b0 u - sum_j (x_j^2 L_j + x_j^-2 R_j).
            for (proof.l, 0..) |lj, j| {
                const x = challenges[j];
                const x_sq = x.mul(x);
                const x_inv_sq = x.inv().mul(x.inv());
                rhs = rhs.sub(lj.mul(x_sq));
                rhs = rhs.sub(proof.r[j].mul(x_inv_sq));
            }

            if (!commitment.eq(rhs)) return error.VerificationFailed;
        }

        /// Per-generator folding scalars: g_i contributes with s[i] and h_i
        /// with s[i]^-1, matching the prover's fold direction.
        fn generatorScalars(self: Self, challenges: []const F) ![]F {
            const log_n = challenges.len;

            const s = try self.allocator.alloc(F, self.n);
            for (0..self.n) |i| s[i] = F.one();

            var n = self.n;
            var round: usize = 0;
            while (n > 1) {
                const half = n / 2;
                const x = challenges[round];
                const x_inv = x.inv();

                for (0..self.n) |i| {
                    if ((i >> @intCast(log_n - 1 - round)) & 1 == 0) {
                        s[i] = s[i].mul(x_inv);
                    } else {
                        s[i] = s[i].mul(x);
                    }
                }
                n = half;
                round += 1;
            }
            return s;
        }
    };
}

pub const MerkleTree = merkle.MerkleTree;

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "IPA prove and verify round-trip" {
    const F = zf.M31;
    const alloc = testing.allocator;
    const n = 8;

    var seed: [32]u8 = undefined;
    std.mem.writeInt(u64, seed[0..8], 0xDEADBEEF, .little);
    var ipa = try Ipa(F).init(alloc, n, seed);
    defer ipa.deinit();

    var prng = std.Random.DefaultPrng.init(1234);
    const rnd = prng.random();
    const a = try alloc.alloc(F, n);
    defer alloc.free(a);
    const b = try alloc.alloc(F, n);
    defer alloc.free(b);
    for (a) |*x| x.* = F.random(rnd);
    for (b) |*x| x.* = F.random(rnd);

    const c = try Ipa(F).innerProduct(a, b);
    const commitment = try ipa.commit(a, b, c);

    const proof = try ipa.prove(alloc, a, b);
    defer proof.deinit(alloc);

    try ipa.verify(commitment, &proof);

    // Wrong commitment must fail
    try testing.expectError(
        error.VerificationFailed,
        ipa.verify(commitment.add(F.one()), &proof),
    );
}

test "IPA proof is bound to its generator setup" {
    const F = zf.M31;
    const alloc = testing.allocator;
    const n = 8;

    var seed_a: [32]u8 = undefined;
    var seed_b: [32]u8 = undefined;
    std.mem.writeInt(u64, seed_a[0..8], 1, .little);
    std.mem.writeInt(u64, seed_b[0..8], 2, .little);
    var ipa_a = try Ipa(F).init(alloc, n, seed_a);
    defer ipa_a.deinit();
    var ipa_b = try Ipa(F).init(alloc, n, seed_b);
    defer ipa_b.deinit();

    var prng = std.Random.DefaultPrng.init(99);
    const rnd = prng.random();
    const a = try alloc.alloc(F, n);
    defer alloc.free(a);
    const b = try alloc.alloc(F, n);
    defer alloc.free(b);
    for (a) |*x| x.* = F.random(rnd);
    for (b) |*x| x.* = F.random(rnd);

    // Proof made under ipa_a's setup must not verify under ipa_b's:
    // challenges are derived from a transcript bound to the generators.
    const c_a = try Ipa(F).innerProduct(a, b);
    const C_a = try ipa_a.commit(a, b, c_a);
    const proof = try ipa_a.prove(alloc, a, b);
    defer proof.deinit(alloc);

    try ipa_a.verify(C_a, &proof);
    try testing.expectError(
        error.VerificationFailed,
        ipa_b.verify(try ipa_b.commit(a, b, c_a), &proof),
    );
}

test {
    std.testing.refAllDecls(@This());
}

test "IPA refuses vectors of different lengths" {
    const F = zf.M31;
    const alloc = std.testing.allocator;

    const a = [_]F{ F.fromInt(1), F.fromInt(2), F.fromInt(3), F.fromInt(4) };
    const b = [_]F{ F.fromInt(5), F.fromInt(6) };

    try testing.expectError(error.LengthMismatch, Ipa(F).innerProduct(&a, &b));

    const seed: [32]u8 = [_]u8{0x42} ** 32;
    var ipa = try Ipa(F).init(alloc, 4, seed);
    defer ipa.deinit();

    try testing.expectError(error.LengthMismatch, ipa.commit(&a, &b, F.fromInt(1)));
    try testing.expectError(error.LengthMismatch, ipa.prove(alloc, &a, &b));
}

test "IPA refuses a proof whose halves differ in length" {
    const F = zf.M31;
    const alloc = std.testing.allocator;

    const seed: [32]u8 = [_]u8{0x42} ** 32;
    var ipa = try Ipa(F).init(alloc, 4, seed);
    defer ipa.deinit();

    const l = try alloc.alloc(F, 4);
    defer alloc.free(l);
    @memset(l, F.fromInt(1));
    const r = try alloc.alloc(F, 2);
    defer alloc.free(r);
    @memset(r, F.fromInt(2));
    const proof = Ipa(F).Proof{ .l = l, .r = r, .a0 = F.fromInt(1), .b0 = F.fromInt(1) };

    try testing.expectError(error.MalformedProof, ipa.verify(F.fromInt(1), &proof));
}
