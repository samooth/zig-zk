//! The contract an AIR must satisfy to be used by `GenericStark`.
//!
//! The prover never instantiates an "AIR framework" type: it reads a set of
//! declarations off the AIR type itself. That is a fine design for comptime
//! monomorphisation, but it means the contract used to live only as scattered
//! accesses inside `stark.zig`, and nothing checked the mandatory part. Forgetting
//! a declaration produced an error from deep inside the prover that never
//! mentioned what was missing.
//!
//! `assertAir` moves the contract here and checks it at compile time, so a
//! malformed AIR fails where it is written.
//!
//! # Mandatory declarations
//!
//! | Declaration | Signature |
//! |---|---|
//! | `num_columns` | comptime int, at least 1 |
//! | `num_transition_constraints` | comptime int |
//! | `num_boundary` | comptime int |
//! | `PublicInputs` | any type |
//! | `evalTransition` | `fn (F, []const F, []const F, []F) void` |
//! | `maxConstraintDegree` | `fn (usize) usize` |
//! | `boundaryAssertions` | `fn (PublicInputs, usize, []BoundaryAssertion) void` |
//! | `generateTrace` | `fn (Allocator, usize) ![]const []const F` |
//! | `freeTrace` | `fn (Allocator, []const []const F) void` |
//!
//! # Conditional declarations
//!
//! Declared only when `num_preprocessed > 0`:
//!
//! | Declaration | Signature |
//! |---|---|
//! | `generateTable` | `fn (Allocator, usize) ![]const []const F` |
//! | `freeTable` | `fn (Allocator, []const []const F) void` |
//!
//! Declared only when `num_lookup_relations > 0`, together with
//! `num_lookup_columns`:
//!
//! | Declaration | Signature |
//! |---|---|
//! | `lookup_selector_columns` | `[num_lookup_relations]usize` |
//! | `lookup_key_columns` | `[num_lookup_relations][]const usize` |
//! | `lookup_table_columns` | `[num_lookup_relations][]const usize` |
//! | `lookup_multiplicity_columns` | `[num_lookup_relations]usize` |
//!
//! `num_preprocessed`, `num_lookup_columns` and `num_lookup_relations` are
//! optional: absent means zero.

const std = @import("std");

/// A fixed boundary value: column `column` at step `step` must equal `value`.
///
/// Row index is 0-based; the evaluation point is `omega^step` in the trace
/// subgroup H.
pub const BoundaryAssertion = struct {
    column: usize,
    step: usize,
    value: @import("../field/qm31.zig").QM31,
};

fn expect(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError(message);
}

/// Fail at compile time unless `Air` satisfies the contract documented above,
/// with `F` as the field the trace is written in.
pub fn assertAir(comptime Air: type, comptime F: type) void {
    comptime {
        // ---- presence ----
        expect(@hasDecl(Air, "num_columns"), "GenericStark: AIR is missing num_columns (number of trace columns, comptime int)");
        expect(@hasDecl(Air, "num_transition_constraints"), "GenericStark: AIR is missing num_transition_constraints (comptime int)");
        expect(@hasDecl(Air, "num_boundary"), "GenericStark: AIR is missing num_boundary (number of boundary assertions, comptime int)");
        expect(@hasDecl(Air, "PublicInputs"), "GenericStark: AIR is missing PublicInputs (any type, usually a struct)");
        expect(@hasDecl(Air, "evalTransition"), "GenericStark: AIR is missing evalTransition (fill the transition constraint evaluations for one row pair)");
        expect(@hasDecl(Air, "maxConstraintDegree"), "GenericStark: AIR is missing maxConstraintDegree (upper bound on constraint degree as a function of n)");
        expect(@hasDecl(Air, "boundaryAssertions"), "GenericStark: AIR is missing boundaryAssertions (fill the fixed column values)");
        expect(@hasDecl(Air, "generateTrace"), "GenericStark: AIR is missing generateTrace (build a valid trace)");
        expect(@hasDecl(Air, "freeTrace"), "GenericStark: AIR is missing freeTrace (release a trace built by generateTrace)");

        // ---- shape numbers are comptime known ----
        expect(Air.num_columns >= 1, "GenericStark: AIR num_columns must be at least 1");
        expect(Air.num_boundary >= 0 and Air.num_transition_constraints >= 0, "GenericStark: AIR num_boundary and num_transition_constraints must not be negative");

        // ---- exact signatures ----
        expect(@TypeOf(Air.evalTransition) == fn (F, []const F, []const F, []F) void, "GenericStark: AIR evalTransition must have the signature fn (F, []const F, []const F, []F) void");
        expect(@TypeOf(Air.maxConstraintDegree) == fn (usize) usize, "GenericStark: AIR maxConstraintDegree must have the signature fn (usize) usize");
        expect(@TypeOf(Air.boundaryAssertions) == fn (Air.PublicInputs, usize, []BoundaryAssertion) void, "GenericStark: AIR boundaryAssertions must have the signature fn (PublicInputs, usize, []BoundaryAssertion) void");
        expect(@TypeOf(Air.freeTrace) == fn (std.mem.Allocator, []const []const F) void, "GenericStark: AIR freeTrace must have the signature fn (Allocator, []const []const F) void");

        expectTraceFn(Air.generateTrace, F, "generateTrace");

        // ---- conditional on preprocessed columns ----
        const n_pre: usize = if (@hasDecl(Air, "num_preprocessed")) Air.num_preprocessed else 0;
        if (n_pre > 0) {
            expect(@hasDecl(Air, "generateTable"), "GenericStark: AIR declares num_preprocessed but no generateTable (build the preprocessed lookup table)");
            expect(@hasDecl(Air, "freeTable"), "GenericStark: AIR declares num_preprocessed but no freeTable (release the table built by generateTable)");
            expectTraceFn(Air.generateTable, F, "generateTable");
            expect(@TypeOf(Air.freeTable) == fn (std.mem.Allocator, []const []const F) void, "GenericStark: AIR freeTable must have the signature fn (Allocator, []const []const F) void");
        }

        // ---- conditional on lookups ----
        const n_rel: usize = if (@hasDecl(Air, "num_lookup_relations")) Air.num_lookup_relations else 0;
        if (n_rel > 0) {
            expect(n_pre > 0, "GenericStark: AIR has lookups (num_lookup_relations > 0) but num_preprocessed == 0");
            expect(@hasDecl(Air, "num_lookup_columns") and Air.num_lookup_columns > 0, "GenericStark: AIR has lookups but num_lookup_columns == 0");
            expect(@hasDecl(Air, "lookup_selector_columns"), "GenericStark: AIR with lookups must declare lookup_selector_columns (per relation)");
            expect(@hasDecl(Air, "lookup_key_columns"), "GenericStark: AIR with lookups must declare lookup_key_columns (per relation, per key column)");
            expect(@hasDecl(Air, "lookup_table_columns"), "GenericStark: AIR with lookups must declare lookup_table_columns (per relation, per table column)");
            expect(@hasDecl(Air, "lookup_multiplicity_columns"), "GenericStark: AIR with lookups must declare lookup_multiplicity_columns (per relation)");
        }
    }
}

/// `generateTrace` and `generateTable` return an inferred error set, so the error
/// union is unwrapped and only the payload and parameters are pinned.
fn expectTraceFn(comptime func: anytype, comptime F: type, comptime name: []const u8) void {
    comptime {
        const info = @typeInfo(@TypeOf(func));
        if (info != .@"fn") {
            @compileError("GenericStark: AIR " ++ name ++ " must be a function");
        }
        const params = info.@"fn".params;
        expect(params.len == 2, "GenericStark: AIR " ++ name ++ " must take (allocator, n)");
        expect(params[0].type.? == std.mem.Allocator, "GenericStark: AIR " ++ name ++ " first parameter must be std.mem.Allocator");
        expect(params[1].type.? == usize, "GenericStark: AIR " ++ name ++ " second parameter must be usize");

        const ret = info.@"fn".return_type.?;
        if (@typeInfo(ret) != .error_union) {
            @compileError("GenericStark: AIR " ++ name ++ " must return ![]const []const F (an error union)");
        }
        expect(@typeInfo(ret).error_union.payload == []const []const F, "GenericStark: AIR " ++ name ++ " must return ![]const []const F");
    }
}
