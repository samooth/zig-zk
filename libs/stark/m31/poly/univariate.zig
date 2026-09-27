const std = @import("std");
const M31 = @import("../field/m31.zig").M31;
const QM31 = @import("../field/qm31.zig").QM31;

/// Generic univariate polynomial helpers over a field `F` that provides
/// `zero()`, `one()`, `eq`, `add`, `sub`, `mul`, `neg`, `inv`. Coefficients
/// are stored little-endian (index 0 = constant term).
pub fn Generic(comptime F: type) type {
    return struct {
        /// Evaluate poly (coefficients, length = deg + 1) at x using Horner's rule.
        pub fn eval(poly: []const F, x: F) F {
            var result = F.zero();
            var i = poly.len;
            while (i > 0) {
                i -= 1;
                result = result.mul(x).add(poly[i]);
            }
            return result;
        }

        /// Trim trailing zero coefficients. Returns the number of leading
        /// coefficients that are nonzero (0 for the zero polynomial).
        pub fn trim(poly: []F) usize {
            var n = poly.len;
            while (n > 0 and poly[n - 1].eq(F.zero())) : (n -= 1) {}
            return n;
        }

        pub fn degree(poly: []const F) isize {
            var i: isize = @intCast(poly.len);
            while (i > 0) : (i -= 1) {
                if (!poly[@intCast(i - 1)].eq(F.zero())) return i - 1;
            }
            return -1;
        }

        /// out = a + b (out may alias neither). `error.OutputLength` unless
        /// out.len >= max(a.len, b.len).
        pub fn add(a: []const F, b: []const F, out: []F) error{OutputLength}!void {
            if (out.len < @max(a.len, b.len)) return error.OutputLength;
            var i: usize = 0;
            while (i < out.len) : (i += 1) {
                const va = if (i < a.len) a[i] else F.zero();
                const vb = if (i < b.len) b[i] else F.zero();
                out[i] = va.add(vb);
            }
        }

        /// out = a - b. `error.OutputLength` unless out.len >= max(a.len, b.len).
        pub fn sub(a: []const F, b: []const F, out: []F) error{OutputLength}!void {
            if (out.len < @max(a.len, b.len)) return error.OutputLength;
            var i: usize = 0;
            while (i < out.len) : (i += 1) {
                const va = if (i < a.len) a[i] else F.zero();
                const vb = if (i < b.len) b[i] else F.zero();
                out[i] = va.sub(vb);
            }
        }

        /// out = a * b (schoolbook). `error.OutputLength` unless
        /// out.len == a.len + b.len - 1.
        pub fn mul(a: []const F, b: []const F, out: []F) error{OutputLength}!void {
            if (out.len != a.len + b.len - 1) return error.OutputLength;
            @memset(out, F.zero());
            for (a, 0..) |va, i| {
                for (b, 0..) |vb, j| {
                    out[i + j] = out[i + j].add(va.mul(vb));
                }
            }
        }

        /// out = c * poly. `error.OutputLength` unless out.len >= poly.len.
        pub fn scale(poly: []const F, c: F, out: []F) error{OutputLength}!void {
            if (out.len < poly.len) return error.OutputLength;
            for (poly, 0..) |v, i| out[i] = v.mul(c);
        }

        /// Interpolate the unique polynomial of degree < n through points
        /// (xs[i], ys[i]), i = 0..n-1 (distinct xs), writing coefficients into
        /// `coeffs` (length n). Barycentric/Lagrange, O(n^2).
        ///
        /// `error.InputLengthMismatch` when `ys.len != xs.len` and
        /// `error.OutputLength` when `coeffs.len != n`. Both were asserts, so in
        /// ReleaseFast a short `ys` read past its end instead of failing.
        pub fn interpolate(
            allocator: std.mem.Allocator,
            xs: []const F,
            ys: []const F,
            coeffs: []F,
        ) !void {
            const n = xs.len;
            if (ys.len != n) return error.InputLengthMismatch;
            if (coeffs.len != n) return error.OutputLength;

            // Basis polynomial P(z) = prod_i (z - xs[i]), degree n (length n+1).
            const p = try allocator.alloc(F, n + 1);
            defer allocator.free(p);
            @memset(p, F.zero());
            p[0] = F.one();
            var plen: usize = 1;
            for (xs) |xi| {
                // p = p * (z - xi)
                var j = plen;
                while (j > 0) : (j -= 1) {
                    p[j] = p[j - 1].sub(p[j].mul(xi));
                }
                p[0] = p[0].neg().mul(xi);
                plen += 1;
            }

            // Weights w_i = prod_{j != i} (xs[i] - xs[j]).
            const weights = try allocator.alloc(F, n);
            defer allocator.free(weights);
            for (xs, 0..) |xi, i| {
                var w = F.one();
                for (xs, 0..) |xj, j| {
                    if (i != j) w = w.mul(xi.sub(xj));
                }
                weights[i] = w;
            }

            // Result = sum_i y_i / w_i * (P(z) / (z - xs[i]))
            const acc = try allocator.alloc(F, n);
            defer allocator.free(acc);
            @memset(acc, F.zero());

            const tmp2 = try allocator.alloc(F, n);
            defer allocator.free(tmp2);

            for (xs, 0..) |xi, i| {
                const scale_f = ys[i].mul(weights[i].inv());
                // synthetic division: Q(z) = P(z) / (z - xi), degree n-1
                // Q[n-1] = P[n]; Q[j-1] = P[j] + xi * Q[j]
                tmp2[n - 1] = p[n];
                var j = n - 1;
                while (j > 0) : (j -= 1) {
                    tmp2[j - 1] = p[j].add(xi.mul(tmp2[j]));
                }
                for (tmp2, 0..) |v, k| {
                    acc[k] = acc[k].add(v.mul(scale_f));
                }
            }

            @memcpy(coeffs, acc);
        }

        /// Vanishing polynomial on the point set `points`: prod_i (z - points[i]).
        /// `error.OutputLength` unless out.len == points.len + 1.
        pub fn vanishPoly(points: []const F, out: []F) error{OutputLength}!void {
            if (out.len != points.len + 1) return error.OutputLength;
            @memset(out, F.zero());
            out[0] = F.one();
            var len: usize = 1;
            for (points) |xi| {
                var j = len;
                while (j > 0) : (j -= 1) {
                    out[j] = out[j - 1].sub(out[j].mul(xi));
                }
                out[0] = out[0].neg().mul(xi);
                len += 1;
            }
        }
    };
}

/// Univariate polynomial helpers over M31 (see `Generic`).
pub const Univariate = Generic(M31);

/// Univariate polynomial helpers over QM31 (see `Generic`).
pub const UnivariateQM31 = Generic(QM31);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "univariate horner eval" {
    // 2 + 3x + x^2 evaluated at x=5 => 42
    const poly = [_]M31{ M31.fromInt(2), M31.fromInt(3), M31.fromInt(1) };
    try std.testing.expect(Univariate.eval(&poly, M31.fromInt(5)).eq(M31.fromInt(42)));
    // at x=0 => constant term
    try std.testing.expect(Univariate.eval(&poly, M31.zero()).eq(M31.fromInt(2)));
}

test "univariate mul" {
    // (1 + x)(1 - x) = 1 - x^2
    var out: [3]M31 = undefined;
    const a = [_]M31{ M31.one(), M31.one() };
    const b = [_]M31{ M31.one(), M31.one().neg() };
    try Univariate.mul(&a, &b, &out);
    try std.testing.expect(out[0].eq(M31.one()));
    try std.testing.expect(out[1].eq(M31.zero()));
    try std.testing.expect(out[2].eq(M31.one().neg()));
}

test "univariate add/sub/scale" {
    var out: [3]M31 = undefined;
    const a = [_]M31{ M31.fromInt(2), M31.fromInt(3) };
    const b = [_]M31{ M31.fromInt(1), M31.fromInt(0), M31.fromInt(5) };
    try Univariate.add(&a, &b, &out);
    try std.testing.expect(out[0].eq(M31.fromInt(3)));
    try std.testing.expect(out[1].eq(M31.fromInt(3)));
    try std.testing.expect(out[2].eq(M31.fromInt(5)));
    try Univariate.sub(&a, &b, &out);
    try std.testing.expect(out[0].eq(M31.fromInt(1)));
    try std.testing.expect(out[1].eq(M31.fromInt(3)));
    try std.testing.expect(out[2].eq(M31.fromInt(5).neg()));
    try Univariate.scale(&b, M31.fromInt(2), &out);
    try std.testing.expect(out[0].eq(M31.fromInt(2)));
    try std.testing.expect(out[2].eq(M31.fromInt(10)));
}

test "univariate interpolate round-trips" {
    var prng = std.Random.DefaultPrng.init(123);
    const rnd = prng.random();
    const n = 8;
    // distinct x values
    var xs: [n]M31 = undefined;
    for (0..n) |i| xs[i] = M31.fromInt(@intCast(i + 1));
    var ys: [n]M31 = undefined;
    for (0..n) |i| ys[i] = M31.fromInt(rnd.uintLessThan(u32, M31.MODULUS));

    var coeffs: [n]M31 = undefined;
    Univariate.interpolate(std.testing.allocator, &xs, &ys, &coeffs) catch unreachable;

    for (0..n) |i| {
        try std.testing.expect(Univariate.eval(&coeffs, xs[i]).eq(ys[i]));
    }
}

test "univariate interpolate recovers linear" {
    // y = 3x + 2 through (0,2), (1,5)
    const xs = [_]M31{ M31.zero(), M31.one() };
    const ys = [_]M31{ M31.fromInt(2), M31.fromInt(5) };
    var coeffs: [2]M31 = undefined;
    Univariate.interpolate(std.testing.allocator, &xs, &ys, &coeffs) catch unreachable;
    try std.testing.expect(coeffs[0].eq(M31.fromInt(2)));
    try std.testing.expect(coeffs[1].eq(M31.fromInt(3)));
}

test "univariate vanish poly" {
    const xs = [_]M31{ M31.fromInt(1), M31.fromInt(2), M31.fromInt(3) };
    var v: [4]M31 = undefined;
    try Univariate.vanishPoly(&xs, &v);
    for (xs) |x| {
        try std.testing.expect(Univariate.eval(&v, x).eq(M31.zero()));
    }
    // leading coefficient is 1
    try std.testing.expect(v[3].eq(M31.one()));
}

test "univariate refuses buffers of the wrong length" {
    const a = [_]M31{ M31.fromInt(1), M31.fromInt(2), M31.fromInt(3) };
    const b = [_]M31{ M31.fromInt(4), M31.fromInt(5) };
    var three: [3]M31 = undefined;
    var two: [2]M31 = undefined;
    var five: [5]M31 = undefined;

    // add and sub need room for the longer input, so a short out is refused and
    // a long one is not: the extra entries are the zero padding.
    try std.testing.expectError(error.OutputLength, Univariate.add(&a, &b, &two));
    try std.testing.expectError(error.OutputLength, Univariate.sub(&a, &b, &two));
    try Univariate.add(&a, &b, &five);
    try Univariate.sub(&a, &b, &five);

    // mul needs the exact size, in both directions.
    var four: [4]M31 = undefined;
    try std.testing.expectError(error.OutputLength, Univariate.mul(&a, &b, &five));
    try std.testing.expectError(error.OutputLength, Univariate.mul(&a, &b, &three));
    try Univariate.mul(&a, &b, &four);
    // a * b for a of length 3 and b of length 2 is 3 + 2 - 1 = 4.
    try std.testing.expect(four[0].eq(a[0].mul(b[0])));
    try std.testing.expect(four[3].eq(a[2].mul(b[1])));

    try std.testing.expectError(error.OutputLength, Univariate.scale(&a, M31.one(), &two));
    try Univariate.scale(&a, M31.one(), &three);

    // vanishPoly wants points.len + 1, no more and no less.
    const xs = [_]M31{ M31.fromInt(1), M31.fromInt(2) };
    var v3: [3]M31 = undefined;
    try std.testing.expectError(error.OutputLength, Univariate.vanishPoly(&xs, &two));
    try Univariate.vanishPoly(&xs, &v3);
}

test "interpolate refuses inputs that disagree and a coeffs buffer of the wrong size" {
    const xs = [_]M31{ M31.fromInt(1), M31.fromInt(2), M31.fromInt(3) };
    const ys = [_]M31{ M31.fromInt(4), M31.fromInt(5), M31.fromInt(6) };
    var coeffs: [3]M31 = undefined;
    var four: [4]M31 = undefined;

    // ys has to be as long as xs: two different mistakes, two errors.
    try std.testing.expectError(
        error.InputLengthMismatch,
        Univariate.interpolate(std.testing.allocator, &xs, ys[0..2], &coeffs),
    );
    try std.testing.expectError(
        error.OutputLength,
        Univariate.interpolate(std.testing.allocator, &xs, &ys, &four),
    );
    try Univariate.interpolate(std.testing.allocator, &xs, &ys, &coeffs);
    for (xs, ys) |x, y| {
        try std.testing.expect(Univariate.eval(&coeffs, x).eq(y));
    }
}
