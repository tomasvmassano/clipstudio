import { test } from "node:test";
import assert from "node:assert/strict";
import { commentReasonLabel, engagement, kindLabel, KINDS, nextRun, reelLink } from "../src/lib/comments-format.ts";

test("kindLabel conhece os quatro tipos e cai para por classificar", () => {
  assert.equal(KINDS.length, 4);
  assert.equal(kindLabel("discorda"), "Discorda");
  assert.equal(kindLabel("outro_angulo"), "Outro ponto de vista");
  assert.equal(kindLabel(null), "Por classificar");
  assert.equal(kindLabel("xpto"), "Por classificar");
});
test("commentReasonLabel", () => {
  assert.equal(commentReasonLabel("repetido"), "Já respondemos");
  assert.equal(commentReasonLabel(undefined), "—");
});
test("reelLink só aceita https", () => {
  assert.equal(reelLink("https://www.instagram.com/reel/abc/"), "https://www.instagram.com/reel/abc/");
  assert.equal(reelLink("javascript:alert(1)"), null);
  assert.equal(reelLink("http://x.com"), null);
  assert.equal(reelLink("não é link"), null);
  assert.equal(reelLink(null), null);
});
test("engagement com singular e plural", () => {
  assert.equal(engagement(120, 14), "120 gostos · 14 respostas");
  assert.equal(engagement(1, 1), "1 gosto · 1 resposta");
  assert.equal(engagement(null, 3), "3 respostas");
  assert.equal(engagement(null, null), "");
});
test("nextRun soma três dias", () => {
  assert.equal(nextRun("2026-11-09T06:00:00Z")?.toISOString(), "2026-11-12T06:00:00.000Z");
  assert.equal(nextRun(null), null);
  assert.equal(nextRun("lixo"), null);
});
