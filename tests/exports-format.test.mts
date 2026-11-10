import assert from "node:assert/strict";
import { test } from "node:test";
import { exportName, exportDay, dayLabel, sizeText, durText } from "../src/lib/exports-format.ts";

const base = { title: "x.mp4", tags: ["hook_2"], content: { n: 3, date: "2026-11-10", tema: "t" }, style: "S17", version_no: 2, finished_at: "2026-11-10T19:30:00Z", created_at: "2026-11-10T19:00:00Z" };

test("nome do vídeo exportado (W10-44)", () => {
  assert.equal(exportName(base), "Guião 03 · Hook 2 · S17 · v2");
  assert.equal(exportName({ ...base, content: null, tags: [], style: null, version_no: null }), "x.mp4");
});

test("dia no fuso do cliente e rótulos", () => {
  assert.equal(exportDay({ ...base, finished_at: "2026-11-10T21:30:00Z" }, "Asia/Dubai"), "2026-11-11");
  assert.equal(dayLabel("2026-11-11", "2026-11-11", "Asia/Dubai"), "Hoje");
  assert.equal(dayLabel("2026-11-10", "2026-11-11", "Asia/Dubai"), "Ontem");
  assert.match(dayLabel("2026-11-08", "2026-11-11", "Asia/Dubai"), /8/);
});

test("tamanho e duração", () => {
  assert.equal(sizeText(45_600_000), "46 MB");
  assert.equal(sizeText(1_250_000_000), "1,3 GB");
  assert.equal(durText(42.4), "42 s");
  assert.equal(durText(75), "1:15");
  assert.equal(durText(null), "");
});
