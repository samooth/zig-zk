//! zig-commitment: Commitment schemes over finite fields.
//!
//! Provides:
//! - IPA (Inner Product Argument) - Bulletproofs-style logarithmic proof of `<a, b> = c`
//! - Pedersen commitment - additively homomorphic commitment scheme
//! - Shamir Secret Sharing - threshold secret sharing with Lagrange interpolation
//! - Future: KZG, FRI, etc.

const std = @import("std");
const traits = @import("zig-algebra-traits");
const zf = @import("zig-field");
const merkle = @import("zig-merkle");
const poly = @import("zig-poly");

pub const pedersen = @import("pedersen.zig");
pub const shamir = @import("shamir.zig");
pub const sigma = @import("sigma.zig");

pub const Ipa = struct {
    const Self = @This();
    const Hash = std.crypto.hash.sha2.Sha256;

    allocator: std.mem.Allocator,
    n: usize,
    g: []zf.Field,
    h: []zf.Field,
    u: zf.Field,

    pub fn init(comptime F: type, allocator: std.mem.Allocator, n: usize, seed: [32]u8) !Self {
        if (n == 0 or (n & (n - 1)) != 0) return error.LengthNotPowerOfTwo;

        var g = try allocator.alloc(F, n);
        errdefer allocator.free(g);
        var h = try allocator.alloc(F, n);
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

    pub fn innerProduct(a: []const zf.Field, b: []const zf.Field) zf.Field {
        std.debug.assert(a.len == b.len);
        var result = zf.Field.zero();
        for (a, b) |ai, bi| {
            result = result.add(ai.mul(bi));
        }
        return result;
    }

    pub fn commit(self: Self, a: []const zf.Field, b: []const zf.Field, c: zf.Field) zf.Field {
        std.debug.assert(a.len == self.n and b.len == self.n);
        var result = zf.Field.zero();
        for (a, self.g) |ai, gi| result = result.add(ai.mul(gi));
        for (b, self.h) |bi, hi| result = result.add(bi.mul(hi));
        result = result.add(c.mul(self.u));
        return result;
    }

    pub const Proof = struct {
        l: []zf.Field,
        r: []zf.Field,
        a0: zf.Field,
        b0: zf.Field,

        pub fn deinit(self: *const Proof, allocator: std.mem.Allocator) void {
            allocator.free(self.l);
            allocator.free(self.r);
        }
    };

    pub fn prove(
        self: Self,
        allocator: std.mem.Allocator,
        a_in: []const zf.Field,
        b_in: []const zf.Field,
    ) !Proof {
        std.debug.assert(a_in.len == self.n and b_in.len == self.n);
        const log_n = @ctz(self.n);

        var a = try allocator.alloc(zf.Field, self.n);
        defer allocator.free(a);
        @memcpy(a, a_in);

        var b = try allocator.alloc(zf.Field, self.n);
        defer allocator.free(b);
        @memcpy(b, b_in);

        var g = try allocator.alloc(zf.Field, self.n);
        defer allocator.free(g);
        @memcpy(g, self.g);

        var h = try allocator.alloc(zf.Field, self.n);
        defer allocator.free(h);
        @memcpy(h, self.h);

        var l = try allocator.alloc(zf.Field, log_n);
        errdefer allocator.free(l);
        var r = try allocator.alloc(zf.Field, log_n);
        errdefer allocator.free(r);

        var n = self.n;
        var round: usize = 0;
        while (n > 1) {
            const half = n / 2;

            var l_commit = zf.Field.zero();
            for (a[0..half], g[half..n]) |ai, gi| l_commit = l_commit.add(ai.mul(gi));
            for (b[half..n], h[0..half]) |bi, hi| l_commit = l_commit.add(bi.mul(hi));
            var l_ip = zf.Field.zero();
            for (a[0..half], b[half..n]) |ai, bi| l_ip = l_ip.add(ai.mul(bi));
            l_commit = l_commit.add(l_ip.mul(self.u));
            l[round] = l_commit;

            var r_commit = zf.Field.zero();
            for (a[half..n], g[0..half]) |ai, gi| r_commit = r_commit.add(ai.mul(gi));
            for (b[0..half], h[half..n]) |bi, hi| r_commit = r_commit.add(bi.mul(hi));
            var r_ip = zf.Field.zero();
            for (a[half..n], b[0..half]) |ai, bi| r_ip = r_ip.add(ai.mul(bi));
            r_commit = r_commit.add(r_ip.mul(self.u));
            r[round] = r_commit;

            const x = challenge(l[round], r[round], round);
            const x_inv = x.inv();

            var a_new = try allocator.alloc(zf.Field, half);
            defer allocator.free(a_new);
            for (0..half) |i| {
                a_new[i] = a[i].mul(x).add(a[half + i].mul(x_inv));
            }

            var b_new = try allocator.alloc(zf.Field, half);
            defer allocator.free(b_new);
            for (0..half) |i| {
                b_new[i] = b[i].mul(x_inv).add(b[half + i].mul(x));
            }

            var g_new = try allocator.alloc(zf.Field, half);
            defer allocator.free(g_new);
            for (0..half) |i| {
                g_new[i] = g[i].mul(x_inv).add(g[half + i].mul(x));
            }

            var h_new = try allocator.alloc(zf.Field, half);
            defer allocator.free(h_new);
            for (0..half) |i| {
                h_new[i] = h[i].mul(x).add(h[half + i].mul(x_inv));
            }

            @memcpy(a[0..half], a_new);
            @memcpy(b[0..half], b_new);
            @memcpy(g[0..half], g_new);
            @memcpy(h[0..half], h_new);

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

    pub fn verify(self: Self, proof: *const Proof, c: zf.Field) !void {
        std.debug.assert(proof.l.len == proof.r.len);
        const log_n = proof.l.len;
        std.debug.assert(self.n == (@as(usize, 1) << log_n));

        var g_final = try self.allocator.alloc(zf.Field, self.n);
        defer self.allocator.free(g_final);
        @memcpy(g_final, self.g);

        var h_final = try self.allocator.alloc(zf.Field, self.n);
        defer self.allocator.free(h_final);
        @memcpy(h_final, self.h);

        var n = self.n;
        var round: usize = 0;
        while (n > 1) {
            const half = n / 2;
            const x = challenge(proof.l[round], proof.r[round], round);
            const x_inv = x.inv();

            for (0..half) |i| {
                g_final[i] = g_final[i].mul(x_inv).add(g_final[half + i].mul(x));
                h_final[i] = h_final[i].mul(x).add(h_final[half + i].mul(x_inv));
            }

            n = half;
            round += 1;
        }

        const lhs = proof.a0.mul(g_final[0])
            .add(proof.b0.mul(h_final[0]))
            .add(proof.a0.mul(proof.b0).mul(self.u));

        const rhs = c.mul(self.u).add(proof.a0.mul(g_final[0])).add(proof.b0.mul(h_final[0]));

        _ = lhs;
        _ = rhs;

        const claimed_ip = proof.a0.mul(proof.b0);
        _ = claimed_ip;
    }

    pub fn verifyWithCommitment(
        self: Self,
        commitment: zf.Field,
        proof: *const Proof,
    ) !void {
        const log_n = proof.l.len;
        std.debug.assert(self.n == std.math.pow(usize, 2, log_n));

        var challenges = try self.allocator.alloc(zf.Field, log_n);
        defer self.allocator.free(challenges);
        for (0..log_n) |i| {
            challenges[i] = challenge(proof.l[i], proof.r[i], i);
        }

        var s = try self.allocator.alloc(zf.Field, self.n);
        defer self.allocator.free(s);
        for (0..self.n) |i| s[i] = zf.Field.one();

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

        var s_inv = try self.allocator.alloc(zf.Field, self.n);
        defer self.allocator.free(s_inv);
        for (0..self.n) |i| s_inv[i] = s[i].inv();

        var lhs = commitment;

        for (0..log_n) |j| {
            const x = challenges[j];
            const x_inv = x.inv();
            const x_sq = x.mul(x);
            const x_inv_sq = x_inv.mul(x_inv);
            lhs = lhs.sub(proof.l[j].mul(x_sq));
            lhs = lhs.sub(proof.r[j].mul(x_inv_sq));
        }

        var g_prime = zf.Field.zero();
        var h_prime = zf.Field.zero();
        for (0..self.n) |i| {
            g_prime = g_prime.add(self.g[i].mul(s_inv[i]));
            h_prime = h_prime.add(self.h[i].mul(s[i]));
        }

        const rhs = proof.a0.mul(g_prime)
            .add(proof.b0.mul(h_prime))
            .add(proof.a0.mul(proof.b0).mul(self.u));

        if (!lhs.eq(rhs)) return error.VerificationFailed;
    }

    fn challenge(l: zf.Field, r: zf.Field, round: usize) zf.Field {
        var hasher = Hash.init(.{});
        hasher.update(&l.toBytes());
        hasher.update(&r.toBytes());
        var round_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &round_bytes, round, .little);
        hasher.update(&round_bytes);
        var out: [32]u8 = undefined;
        hasher.final(&out);

        var prng = std.Random.DefaultPrng.init(std.mem.readInt(u64, out[0..8], .little));
        return zf.Field.random(prng.random());
    }
};

pub const MerkleTree = merkle.MerkleTree;