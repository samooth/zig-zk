const std = @import("std");

// Module namespaces
pub const core = @import("core/lib.zig");
pub const binius = @import("binius/lib.zig");
pub const m31_lib = @import("m31/lib.zig");

// M31 / CM31 / QM31 field tower
pub const m31 = @import("m31/field/m31.zig");
pub const cm31 = @import("m31/field/cm31.zig");
pub const qm31 = @import("m31/field/qm31.zig");
pub const field_simd = @import("m31/field/simd.zig");

// Circle geometry
pub const circle_point = @import("m31/circle/point.zig");
pub const circle_domain = @import("m31/circle/domain.zig");
pub const circle_coset = @import("m31/circle/coset.zig");

// NTT
pub const ntt_classic = @import("m31/ntt/classic.zig");
pub const ntt_simd = @import("m31/ntt/simd.zig");
pub const ntt_circle = @import("m31/ntt/circle.zig");

// AIR abstractions
pub const air_contract = @import("m31/air/contract.zig");

pub const bit_utils = @import("core/bit_utils.zig");
pub const univariate = @import("m31/poly/univariate.zig");

pub const hash = @import("core/hash/hash.zig");
pub const merkle = @import("core/merkle/merkle.zig");
pub const channel = @import("zig-transcript"); // vendored channel retired; zig-transcript hosts it
pub const fri = @import("m31/fri.zig");
pub const stark = @import("m31/stark.zig");

test {
    std.testing.refAllDecls(@This());
}
