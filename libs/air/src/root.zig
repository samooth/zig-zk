// SPDX-License-Identifier: MIT OR Apache-2.0

//! zig-air: Generic Algebraic Intermediate Representation (AIR) framework.
//!
//! Provides the core data structures for defining STARK arithmetic constraints
//! over any field. This is a field-agnostic framework extracted from zig-stark's
//! M31 AIR implementation.
//!
//! # Components
//! - `Air(BaseField, PublicInputs)` — Main AIR type with evaluation frame, assertions, constraints
//! - `BoundaryConstraint(Field)` — Boundary constraints (fixed values at specific steps)
//! - `TransitionConstraint(Field)` — Transition constraints (relations between rows)
//! - `EvaluationFrame(Field)` — Current/next row pair for constraint evaluation
//! - `ExecutionTrace(Field)` — Full execution trace matrix with allocator

const std = @import("std");
const traits = @import("zig-algebra-traits");

// ============================================================================
// AIR: Algebraic Intermediate Representation
// ============================================================================

/// An AIR definition over a base field with public inputs.
///
/// This is the top-level type that defines:
/// - `EvaluationFrame` — current/next row for constraint evaluation
/// - `Assertion` — fixed column values at specific steps
/// - `Constraint` — polynomial constraints of a given degree
///
/// # Constraints
/// `BaseField` must satisfy `FieldTrait`. `PublicInputs` is any type.
pub fn Air(comptime BaseField: type, comptime PublicInputs: type) type {
    _ = PublicInputs;
    return struct {
        pub const EvaluationFrame = struct {
            current: []const BaseField,
            next: []const BaseField,
        };

        /// A fixed boundary condition: column `column` at step `step` must equal `value`.
        pub const Assertion = struct {
            column: usize,
            step: usize,
            value: BaseField,
        };

        /// A transition constraint of degree `degree`.
        /// `evaluate(frame, result)` fills `result` with the constraint polynomial evaluations.
        pub const Constraint = struct {
            degree: usize,
            evaluate: *const fn (frame: @This().EvaluationFrame, result: []BaseField) void,
        };
    };
}

// ============================================================================
// Boundary & Transition Constraints
// ============================================================================

/// A boundary constraint for a specific field.
pub fn BoundaryConstraint(comptime Field: type) type {
    return struct {
        column: usize,
        step: usize,
        value: Field,
    };
}

/// A transition constraint for a specific field.
pub fn TransitionConstraint(comptime Field: type) type {
    return struct {
        degree: usize,
        evaluate: *const fn (current: []const Field, next: []const Field, result: []Field) void,
    };
}

// ============================================================================
// Evaluation Frame
// ============================================================================

/// A pair of consecutive rows for evaluating transition constraints.
pub fn EvaluationFrame(comptime Field: type) type {
    return struct {
        current: []const Field,
        next: []const Field,

        pub fn new(current: []const Field, next: []const Field) @This() {
            return .{ .current = current, .next = next };
        }
    };
}

// ============================================================================
// Execution Trace
// ============================================================================

/// An execution trace matrix: `num_rows` × `num_cols` field elements.
///
/// Owns its data and allocator. Use `deinit()` to free.
pub fn ExecutionTrace(comptime Field: type) type {
    return struct {
        const Self = @This();
        data: []Field,
        num_rows: usize,
        num_cols: usize,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, num_rows: usize, num_cols: usize) !Self {
            const data = try allocator.alloc(Field, num_rows * num_cols);
            @memset(data, Field.zero());
            return .{
                .data = data,
                .num_rows = num_rows,
                .num_cols = num_cols,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn get(self: Self, row: usize, col: usize) Field {
            return self.data[row * self.num_cols + col];
        }

        pub fn set(self: *Self, row: usize, col: usize, value: Field) void {
            self.data[row * self.num_cols + col] = value;
        }

        pub fn getRow(self: Self, row: usize) []const Field {
            return self.data[row * self.num_cols .. (row + 1) * self.num_cols];
        }

        pub fn getCol(self: Self, col: usize, allocator: std.mem.Allocator) ![]Field {
            var result = try allocator.alloc(Field, self.num_rows);
            for (0..self.num_rows) |i| {
                result[i] = self.get(i, col);
            }
            return result;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Minimal F7 field for testing
const F7 = struct {
    const Self = @This();
    value: u64,
    pub const modulus: u64 = 7;
    pub const characteristic: u64 = 7;
    pub const order: u64 = 7;

    pub fn zero() Self { return .{ .value = 0 }; }
    pub fn one() Self { return .{ .value = 1 }; }
    pub fn fromInt(x: u256) Self { return .{ .value = @intCast(x % modulus) }; }
    pub fn toInt(self: Self) u64 { return self.value; }
    pub fn eql(a: Self, b: Self) bool { return a.value == b.value; }
    pub fn add(a: Self, b: Self) Self { return fromInt(a.value + b.value); }
    pub fn sub(a: Self, b: Self) Self { return fromInt(a.value + (modulus - b.value % modulus)); }
    pub fn neg(a: Self) Self { return if (a.value == 0) zero() else fromInt(modulus - a.value); }
    pub fn mul(a: Self, b: Self) Self { return fromInt(a.value * b.value); }
    pub fn inv(a: Self) Self {
        std.debug.assert(!a.isZero());
        return pow(a, modulus - 2);
    }
    pub const inverse = inv;
    pub fn div(a: Self, b: Self) Self { return mul(a, inv(b)); }
    pub fn pow(base: Self, exp: u64) Self {
        var result = one();
        var b = base;
        var e = exp;
        while (e > 0) {
            if (e & 1 == 1) result = mul(result, b);
            b = mul(b, b);
            e >>= 1;
        }
        return result;
    }
    pub fn isZero(self: Self) bool { return self.value == 0; }
    pub fn random() Self { return fromInt(1); }
};

test "Air type instantiation" {
    const MyAir = Air(F7, void);
    const frame = MyAir.EvaluationFrame{
        .current = &[_]F7{ F7.fromInt(1), F7.fromInt(2) },
        .next = &[_]F7{ F7.fromInt(3), F7.fromInt(4) },
    };
    _ = frame;
    try testing.expect(true);
}

test "BoundaryConstraint type" {
    const BC = BoundaryConstraint(F7);
    const bc = BC{ .column = 0, .step = 1, .value = F7.fromInt(3) };
    try testing.expect(bc.value.value == 3);
}

test "TransitionConstraint type" {
    const TC = TransitionConstraint(F7);
    const eval_fn: *const fn (current: []const F7, next: []const F7, result: []F7) void = struct {
        fn eval(current: []const F7, next: []const F7, result: []F7) void {
            result[0] = F7.sub(next[0], current[0]);
        }
    }.eval;
    const tc = TC{ .degree = 1, .evaluate = eval_fn };
    try testing.expect(tc.degree == 1);
}

test "EvaluationFrame creation" {
    const Frame = EvaluationFrame(F7);
    const current = &[_]F7{ F7.fromInt(1), F7.fromInt(2) };
    const next = &[_]F7{ F7.fromInt(3), F7.fromInt(4) };
    const frame = Frame.new(current, next);
    try testing.expect(frame.current[0].value == 1);
    try testing.expect(frame.next[1].value == 4);
}

test "ExecutionTrace basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Trace = ExecutionTrace(F7);
    var trace = try Trace.init(allocator, 4, 3);
    defer trace.deinit();

    try testing.expect(trace.num_rows == 4);
    try testing.expect(trace.num_cols == 3);

    trace.set(0, 0, F7.fromInt(6));
    try testing.expect(trace.get(0, 0).value == 6);

    const row = trace.getRow(0);
    try testing.expect(row.len == 3);

    const col = try trace.getCol(0, allocator);
    defer allocator.free(col);
    try testing.expect(col.len == 4);
}