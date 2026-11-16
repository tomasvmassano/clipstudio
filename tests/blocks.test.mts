import assert from "node:assert/strict";
import { test } from "node:test";
import { corpoParts, isCtaBlock } from "../src/lib/blocks.ts";

test("corpo por blocos, sem linhas vazias (W10-46)", () => {
  const p = corpoParts("Texto do C1.\n\n## C2\nTexto do C2.\n\n## CTA 1\nBook now.\n\n## CTA 2\nTalk to us.");
  assert.deepEqual(p, [
    { label: null, lines: ["Texto do C1."] },
    { label: "C2", lines: ["Texto do C2."] },
    { label: "CTA 1", lines: ["Book now."] },
    { label: "CTA 2", lines: ["Talk to us."] },
  ]);
  assert.deepEqual(corpoParts("## Só bloco\nLinha"), [{ label: "Só bloco", lines: ["Linha"] }]);
});

test("blocos CTA reconhecidos pelo nome", () => {
  assert.ok(isCtaBlock({ key: "cta", label: "CTA" }));
  assert.ok(isCtaBlock({ key: "x_cta_2", label: "CTA 2" }));
  assert.ok(!isCtaBlock({ key: "x_c2", label: "C2" }));
  assert.ok(!isCtaBlock({ key: "x_ctapedia", label: "Ctapedia" }));
});
