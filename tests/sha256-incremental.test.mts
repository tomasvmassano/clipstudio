import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash, randomBytes } from "node:crypto";
import { Sha256 } from "../src/lib/sha256-incremental.ts";

test("igual ao SHA-256 do node para vários tamanhos e fatias", () => {
  for (const n of [0, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 100_003]) {
    const b = randomBytes(n);
    const h = new Sha256();
    for (let i = 0; i < n; i += 37) h.update(b.subarray(i, Math.min(n, i + 37)));
    assert.equal(h.hex(), createHash("sha256").update(b).digest("hex"), `n=${n}`);
  }
});

test("velocidade razoável (64 MiB)", () => {
  const b = randomBytes(64 * 1024 * 1024); const t = Date.now();
  new Sha256().update(b).hex();
  const s = (Date.now() - t) / 1000;
  console.log(`# ${Math.round(64 / s)} MiB/s`);
  assert.ok(s < 5);
});
