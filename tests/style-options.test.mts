import assert from "node:assert/strict";
import { test } from "node:test";
import { styleOptions, optionText } from "../src/lib/style-options.ts";

const engine = { S14: { label: "S14 motor" }, S15: { label: "S15 motor" }, S17: { label: "S17 motor" } };
const cat = [
  { key: "S01", name: "Prova", status: "arquivado" },
  { key: "S13", name: "Faixa de estatuto", status: "ativo" },
  { key: "S15", name: "Destaque vermelho", status: "ativo" },
  { key: "S14", name: "Palavra a palavra", status: "ativo" },
  { key: "S17", name: "Caixa branca", status: "rascunho" },
];

test("só estilos ativos do catálogo que o motor desenha, com o nome do catálogo (W10-41)", () => {
  assert.deepEqual(styleOptions(engine, cat).map((o) => o.label), ["S14 · Palavra a palavra", "S15 · Destaque vermelho"]);
});

test("o estilo atual aparece sempre, marcado com o motivo", () => {
  const o = styleOptions(engine, cat, "S17");
  assert.equal(o[0].id, "S17");
  assert.equal(optionText(o[0]), "S17 · Caixa branca (não ativo)");
  assert.equal(styleOptions(engine, cat, "S13")[0].note, "sem render");
  assert.equal(styleOptions(engine, cat, "S01")[0].note, "sem render");
  assert.equal(styleOptions(engine, [], "S17")[0].note, "fora do catálogo");
  assert.equal(styleOptions(engine, cat, "S15").length, 2);
});

test("sem catálogo: os estilos do motor, marcados", () => {
  const o = styleOptions(engine, null);
  assert.deepEqual(o.map((x) => x.id), ["S14", "S15", "S17"]);
  assert.ok(o.every((x) => x.note === "catálogo indisponível"));
});
