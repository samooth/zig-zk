// Regenerates an equivalent Groth16 vector for the interop test.
//
// This is a *recipe*, not a byte-for-byte reproducer. `powersoftau new` draws
// fresh randomness, so a regenerated zkey differs from the committed one and
// so do vk.json and proof.json. What a re-run does guarantee is the shape: the
// same circuit, the same field, the same five verifying-key pieces and the same
// `IC` convention, produced by the same pinned tool. That is what makes the
// test's parser trustworthy -- it cannot have been fitted to one lucky file.
//
// The circuit is `c <== a * b` with a and b private and c the single public
// signal. It is written as raw R1CS bytes rather than compiled from circom
// because circom is not a dependency here; the layout below is the one
// `r1csfile` writes, and `snarkjs r1cs info` plus `snarkjs wtns check` are run
// afterwards to confirm both files are what they claim to be.
//
// Usage:
//   npm install snarkjs@0.7.6
//   node regenerate.mjs
//   cp vk.json proof.json public.json ../  (or review the diff)

import { writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import * as ff from "ffjavascript";

const SNARKJS = "./node_modules/.bin/snarkjs";
const run = (...args) =>
  execFileSync(SNARKJS, args, { stdio: ["ignore", "ignore", "inherit"] });

const bn = await ff.getCurveFromName("bn128");
const PRIME = bn.Fr.p;
const N8 = 32;

const u32 = (v) => { const b = Buffer.alloc(4); b.writeUInt32LE(Number(v)); return b; };
const u64 = (v) => { const x = BigInt(v); const b = Buffer.alloc(8);
  b.writeUInt32LE(Number(x & 0xffffffffn), 0); b.writeUInt32LE(Number(x >> 32n), 4); return b; };
const le = (v) => { let x = BigInt(v); const b = Buffer.alloc(N8);
  for (let i = 0; i < N8; i++) { b[i] = Number(x & 0xffn); x >>= 8n; } return b; };
const sect = (id, body) => Buffer.concat([u32(id), u64(body.length), body]);
const lc = (terms) => Buffer.concat([u32(Object.keys(terms).length),
  ...Object.entries(terms).map(([w, v]) => Buffer.concat([u32(w), le(v)]))]);

// wire 0 = uno, 1 = c (salida, unica senal publica), 2 = a, 3 = b
const r1cs = Buffer.concat([
  Buffer.from("r1cs"), u32(1), u32(3),
  sect(1, Buffer.concat([u32(N8), le(PRIME), u32(4), u32(1), u32(0), u32(2), u64(8), u32(1)])),
  sect(2, Buffer.concat([lc({ 2: 1n }), lc({ 3: 1n }), lc({ 1: 1n })])),
  sect(3, Buffer.concat([1, 2, 3, 4].map((l) => u64(l)))),
]);
writeFileSync("circuit.r1cs", r1cs);

// testigo: uno, c = 3 * 7 = 21, a = 3, b = 7
const values = [1n, 21n, 3n, 7n];
const wtns = Buffer.concat([
  Buffer.from("wtns"), u32(2), u32(2),
  sect(1, Buffer.concat([u32(N8), le(PRIME), u32(values.length)])),
  sect(2, Buffer.concat(values.map(le))),
]);
writeFileSync("witness.wtns", wtns);

// both files are only trusted once snarkjs itself says so
run("r1cs", "info", "circuit.r1cs");
run("wtns", "check", "circuit.r1cs", "witness.wtns");

run("powersoftau", "new", "bn128", "12", "pot12_0000.ptau");
run("powersoftau", "contribute", "pot12_0000.ptau", "pot12_0001.ptau", "--name=interop", "-e=prueba");
run("powersoftau", "prepare", "phase2", "pot12_0001.ptau", "pot12_final.ptau");
run("groth16", "setup", "circuit.r1cs", "pot12_final.ptau", "c1.zkey");
run("zkey", "contribute", "c1.zkey", "c2.zkey", "-n=interop", "-e=prueba");
run("zkey", "export", "verificationkey", "c2.zkey", "vk.json");
run("groth16", "prove", "c2.zkey", "witness.wtns", "proof.json", "public.json");

// snarkjs must accept its own output before the Zig side is allowed to try
run("groth16", "verify", "vk.json", "public.json", "proof.json");

console.log("vector regenerado: vk.json, proof.json, public.json");
