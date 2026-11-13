import assert from "node:assert/strict";
import { test } from "node:test";
import { youtubeId, titleSimilarity, bestMasterMatch, autoClipCount, momentText } from "../src/lib/clips-format.ts";

test("id do YouTube igual ao servidor (W10-45)", () => {
  assert.equal(youtubeId("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("youtu.be/dQw4w9WgXcQ?si=x"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("https://youtube.com/shorts/dQw4w9WgXcQ"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("https://evil.com/?v=dQw4w9WgXcQ"), null);
  assert.equal(youtubeId("vimeo.com/1"), null);
});

test("liga o título do YouTube ao ficheiro certo", () => {
  const masters = [
    { title: "Podcast_ep12_final.mp4", current: { original_name: "Podcast_ep12_final.mp4" } },
    { title: "Vlog na praia com o Miguel", current: { original_name: "C0045.MP4" } },
  ];
  assert.equal(bestMasterMatch("Vlog na Praia com o Miguel | Dubai", masters)?.title, "Vlog na praia com o Miguel");
  assert.equal(bestMasterMatch("Receita de bolo", masters), null);
  assert.ok(titleSimilarity("Episódio 12: dinheiro", "episodio 12 dinheiro.mp4") > 0.6);
});

test("número automático e tipos de momento", () => {
  assert.equal(autoClipCount(3600), 15);
  assert.equal(autoClipCount(600), 5);
  assert.equal(autoClipCount(null), 8);
  assert.equal(momentText("humor"), "Momento engraçado");
  assert.equal(momentText(undefined), "—");
});
