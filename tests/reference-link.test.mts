import { pasteProblem, refKey } from "../src/lib/reference-link.ts";
const cases: [string, unknown, unknown][] = [
  ["reel com parâmetros", refKey("https://www.instagram.com/reel/CxYz_9-Ab/?igsh=abc"), "instagram:CxYz_9-Ab"],
  ["/p/ sem protocolo", refKey("instagram.com/p/CxYz_9-Ab"), "instagram:CxYz_9-Ab"],
  ["/reels/", refKey("https://instagram.com/reels/CxYz_9-Ab/"), "instagram:CxYz_9-Ab"],
  ["com utilizador", refKey("https://www.instagram.com/autor_x/reel/CxYz_9-Ab/"), "instagram:CxYz_9-Ab"],
  ["maiúsculas contam", refKey("https://www.instagram.com/reel/cxyz_9-ab/") === "instagram:CxYz_9-Ab", false],
  ["tiktok vídeo", refKey("https://www.tiktok.com/@alguem.pt/video/7301234567890123456?lang=pt"), "tiktok:7301234567890123456"],
  ["tiktok /v/", refKey("https://m.tiktok.com/v/7301234567890123456.html"), "tiktok:7301234567890123456"],
  ["tiktok embed", refKey("https://www.tiktok.com/embed/v2/7301234567890123456"), "tiktok:7301234567890123456"],
  ["outro site com o caminho", refKey("https://evil.test/instagram.com/reel/CxYz_9-Ab"), null],
  ["youtube", refKey("https://youtube.com/watch?v=1"), null],
  ["link curto tiktok aceite", pasteProblem("https://vm.tiktok.com/ZMabc123/"), null],
  ["youtube recusado", pasteProblem("https://youtube.com/watch?v=1")?.startsWith("Cola um link de um Reel"), true],
  ["vazio", pasteProblem("  "), "Cola um link."],
];
let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`reference-link: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
