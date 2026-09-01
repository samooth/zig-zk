const std = @import("std");
const zf = @import("zig-field");

/// Builtin M31/CM31/QM31 adapter wrapping zig-field.
/// Matches zig-stark's vendor API surface exactly.
/// M31 = 2^31 - 1
pub const M31 = zf.M31;

/// Re-export Vec8 = @Vector(8, u64) lanes for M31
pub const Vec8 = M31.Vec8;

/// Add 8 lanes
pub fn addVec8(a: Vec8, b: Vec8) Vec8 {
    return M31.addVec8(a, b);
}

/// Subtract 8 lanes
pub fn subVec8(a: Vec8, b: Vec8) Vec8 {
    return M31.subVec8(a, b);
}

/// Multiply 8 lanes (returns unreduced lo+hi; call reduceVec8 after)
pub fn mulVec8(a: Vec8, b: Vec8) Vec8 {
    return M31.mulVec8(a, b);
}

/// Reduce 8 lanes to [0, MOD)
pub fn reduceVec8(v: Vec8) Vec8 {
    return M31.reduceVec8(v);
}

/// Construct Vec8 from zig-stark's @Vector(8, u32) layout
pub fn fromVec8U32(v: @Vector(8, u32)) Vec8 {
    return M31.fromVec8U32(v);
}

/// Convert Vec8 to zig-stark's @Vector(8, u32) layout
pub fn toVec8U32(v: Vec8) @Vector(8, u32) {
    return M31.toVec8U32(v);
}

/// Construct Vec8 from [8]u32 slice
pub fn fromSlice8(slice: []const u32) Vec8 {
    return M31.fromSlice8(slice);
}

/// Construct Vec8 from 8 elements
pub fn fromElements(e0: M31, e1: M31, e2: M31, e3: M31, e4: M31, e5: M31, e6: M31, e7: M31) Vec8 {
    return M31.fromElements(e0, e1, e2, e3, e4, e5, e6, e7);
}

/// Negate 8 lanes
pub fn negVec8(a: Vec8) Vec8 {
    return M31.negVec8(a);
}

/// Constant-time select 8 lanes
pub fn ctSelectVec8(on: bool, a: Vec8, b: Vec8) Vec8 {
    return M31.ctSelectVec8(on, a, b);
}

/// CM31 = M31[i] / (i^2 + 1)
pub const CM31 = zf.CM31;

/// CM31 base-field non-residue: n = -1
pub const CM31_NON_RESIDUE = CM31.NON_RESIDUE;

/// CM31 extension element i where i^2 = NON_RESIDUE
pub const CM31_EXT_NON_RESIDUE = CM31.EXT_NON_RESIDUE;

/// QM31 = CM31[j] / (j^2 + i)
pub const QM31 = zf.QM31;

/// QM31 base-field non-residue: n = -i (in CM31)
pub const QM31_NON_RESIDUE = QM31.NON_RESIDUE;

/// QM31 extension element j where j^2 = NON_RESIDUE
pub const QM31_EXT_NON_RESIDUE = QM31.EXT_NON_RESIDUE;

/// Aliases matching vendor API
pub const M31_MODULUS_U64 = M31.MODULUS;
pub const M31_SIZE = M31.NUM_BYTES;
pub const M31_GENERATOR = M31.GENERATOR;
pub const M31_TWO_ADIC_ROOT = M31.TWO_ADIC_ROOT;

/// Little-endian serialization (matches vendor)
pub fn m31ToBytes(self: M31, out: *[4]u8) void {
    self.toBytes(out);
}

pub fn m31FromBytes(bytes: [4]u8) M31 {
    return M31.fromBytes(bytes) catch unreachable;
}

pub fn cm31ToBytes(self: CM31, out: *[8]u8) void {
    const c0 = self.c0;
    const c1 = self.c1;
    c0.toBytes(out[0..4].*);
    c1.toBytes(out[4..8].*);
}

pub fn cm31FromBytes(bytes: [8]u8) CM31 {
    const c0 = M31.fromBytes(bytes[0..4]) catch unreachable;
    const c1 = M31.fromBytes(bytes[4..8]) catch unreachable;
    return CM31.new(c0, c1);
}

pub fn qm31ToBytes(self: QM31, out: *[16]u8) void {
    const c0 = self.c0;
    const c1 = self.c1;
    c0.toBytes(out[0..8].*);
    c1.toBytes(out[8..16].*);
}

pub fn qm31FromBytes(bytes: [16]u8) QM31 {
    const c0 = CM31.fromBytes(bytes[0..8]) catch unreachable;
    const c1 = CM31.fromBytes(bytes[8..16]) catch unreachable;
    return QM31.new(c0, c1);
}

/// Primitive root of unity for circle FFT (M31 two-adicity = 1 => root = -1)
pub fn m31PrimitiveRootOfUnity(log_size: usize) M31 {
    return M31.primitiveRootOfUnity(log_size);
}

/// Primitive root of unity for CM31
pub fn cm31PrimitiveRootOfUnity(log_size: usize) CM31 {
    return CM31.primitiveRootOfUnity(log_size);
}

/// Primitive root of unity for QM31
pub fn qm31PrimitiveRootOfUnity(log_size: usize) QM31 {
    return QM31.primitiveRootOfUnity(log_size);
}
