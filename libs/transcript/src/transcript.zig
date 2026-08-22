//! Fiat-Shamir transcript for non-interactive proof systems.
//!
//! A **transcript** is a stateful hash chain that absorbs protocol messages
//! (bytes, field elements, curve points) and squeezes deterministic
//! "random" challenges.  It transforms an interactive protocol into a
//! non-interactive one via the Fiat-Shamir heuristic.
//!
//! # Design
//! - **Deterministic**: Given the same sequence of `absorb` calls, `squeeze`
//!   always produces the same output.
//! - **Stateful**: The internal hash accumulator evolves with each operation.
//! - **Forkable**: `clone()` creates an independent copy of the transcript state.
//! - **Domain-separated**: `LabelledTranscript` prefixes every operation with a
//!   human-readable label to prevent cross-protocol attacks.
//!
//! # Underlying Primitive
//! Blake3 is used as the cryptographic sponge.  Each `squeeze` appends an
//! internal counter to the absorbed state before finalizing, ensuring that
//! repeated squeezes without new absorbs still produce fresh challenges.
//!
//! # Quick Start
//! ```zig
//! var t = Transcript.init("my_protocol_v1");
//! t.absorb(&commitment_bytes);
//! t.absorbField(F, a);
//! const challenge = t.squeezeField(F);
//! ```

const std = @import("std");
const traits = @import("zig-algebra-traits");
const Blake3 = @import("zig-hash").Blake3;

/// Fiat-Shamir transcript backed by Blake3.
///
/// # Thread Safety
/// Not thread-safe.  Each thread must use its own transcript instance.
///
/// # Example
/// ```zig
/// var t = Transcript.init("zk-proof-v1");
/// t.absorb("public-input", &public_bytes);
/// t.absorbField(F, witness_commitment);
/// const c1 = t.squeezeField(F);
/// const c2 = t.squeezeField(F); // different from c1
/// ```
pub const Transcript = struct {
    const Self = @This();

    /// Internal Blake3 hasher.  All absorbed data feeds into this state.
    hasher: Blake3,
    /// Monotonic counter appended on every squeeze to guarantee freshness.
    squeeze_counter: u64,

    /// Initialize a new transcript with a protocol label.
    ///
    /// The label should uniquely identify the protocol and version;
    /// it acts as a domain separator against accidental cross-protocol replay.
    pub fn init(label: []const u8) Self {
        var self = Self{
            .hasher = Blake3.init(),
            .squeeze_counter = 0,
        };
        self.absorb(label);
        return self;
    }

    /// Absorb raw bytes into the transcript.
    ///
    /// The length is encoded as a little-endian `u64` prefix to prevent
    /// prefix ambiguity attacks.
    pub fn absorb(self: *Self, data: []const u8) void {
        var len_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &len_bytes, data.len, .little);
        self.hasher.update(&len_bytes);
        self.hasher.update(data);
    }

    /// Absorb a field element.
    ///
    /// `F` must satisfy the `Field` trait and expose `toInt() -> u256`.
    /// The element is serialized as a 32-byte little-endian integer.
    pub fn absorbField(self: *Self, comptime F: type, field: F) void {
        traits.assertField(F);
        const val = field.toInt();
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, val, .little);
        self.absorb(&bytes);
    }

    /// Absorb a slice of field elements.
    pub fn absorbFieldSlice(self: *Self, comptime F: type, fields: []const F) void {
        for (fields) |f| {
            self.absorbField(F, f);
        }
    }

    /// Squeeze `out.len` pseudorandom bytes.
    ///
    /// The squeeze is deterministic: it clones the current hasher state,
    /// appends the internal counter, and finalizes.  The counter is then
    /// incremented so the next squeeze produces different bytes.
    pub fn squeeze(self: *Self, out: []u8) void {
        var temp = self.hasher;
        var counter_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &counter_bytes, self.squeeze_counter, .little);
        temp.update(&counter_bytes);
        temp.finalizeInto(out);
        self.squeeze_counter += 1;
    }

    /// Squeeze a uniformly random field element using rejection sampling.
    ///
    /// `F` must satisfy the `Field` trait and expose `order` and `fromInt`.
    /// The algorithm draws bytes from the transcript until the interpreted
    /// integer is `< order`, guaranteeing a uniform distribution.
    ///
    /// # Example
    /// ```zig
    /// const c = t.squeezeField(F7); // c in [0, 7)
    /// ```
    pub fn squeezeField(self: *Self, comptime F: type) F {
        traits.assertField(F);
        const order = F.order;
        const byte_len = (std.math.log2(order) + 8) / 8;
        var buf: [64]u8 = undefined;

        while (true) {
            self.squeeze(buf[0..byte_len]);
            var val: u256 = 0;
            for (0..byte_len) |i| {
                val = (val << 8) | buf[i];
            }
            if (val < order) {
                return F.fromInt(val);
            }
        }
    }

    /// Squeeze a `u64` challenge.
    pub fn squeezeU64(self: *Self) u64 {
        var buf: [8]u8 = undefined;
        self.squeeze(&buf);
        return std.mem.readInt(u64, &buf, .little);
    }

    /// Squeeze a `u256` challenge.
    pub fn squeezeU256(self: *Self) u256 {
        var buf: [32]u8 = undefined;
        self.squeeze(&buf);
        return std.mem.readInt(u256, &buf, .little);
    }

    /// Create an independent copy of the transcript.
    ///
    /// Both copies will produce identical challenges if fed identical
    /// subsequent absorbs, but diverge after any difference.
    pub fn clone(self: Self) Self {
        return self;
    }

    /// Reset the transcript to a freshly initialized state.
    pub fn reset(self: *Self, label: []const u8) void {
        self.hasher = Blake3.init();
        self.squeeze_counter = 0;
        self.absorb(label);
    }
};

/// Labelled transcript with explicit domain separation.
///
/// Every operation is prefixed with a human-readable label.  This prevents
/// accidental ambiguity when the same byte sequence could be interpreted as
/// different message types in different contexts.
///
/// # Example
/// ```zig
/// var lt = LabelledTranscript.init("zk-proof-v1");
/// lt.absorb("commitment", &commitment);
/// lt.absorb("public-input", &input);
/// const c = lt.squeeze("challenge-round-1", F);
/// ```
pub const LabelledTranscript = struct {
    const Self = @This();

    transcript: Transcript,

    pub fn init(protocol_label: []const u8) Self {
        return .{ .transcript = Transcript.init(protocol_label) };
    }

    /// Absorb raw bytes under a domain label.
    pub fn absorb(self: *Self, label: []const u8, data: []const u8) void {
        self.transcript.absorb(label);
        self.transcript.absorb(data);
    }

    /// Absorb a field element under a domain label.
    pub fn absorbField(self: *Self, label: []const u8, comptime F: type, field: F) void {
        self.transcript.absorb(label);
        self.transcript.absorbField(F, field);
    }

    /// Squeeze a field element under a domain label.
    pub fn squeeze(self: *Self, label: []const u8, comptime F: type) F {
        self.transcript.absorb(label);
        return self.transcript.squeezeField(F);
    }

    /// Squeeze raw bytes under a domain label.
    pub fn squeezeBytes(self: *Self, label: []const u8, out: []u8) void {
        self.transcript.absorb(label);
        self.transcript.squeeze(out);
    }

    /// Fork the labelled transcript.
    pub fn clone(self: Self) Self {
        return .{ .transcript = self.transcript.clone() };
    }
};
