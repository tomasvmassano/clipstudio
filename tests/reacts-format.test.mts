import { allowedVideoUrl, downloadName, guiaoHref, perMille, reasonLabel, scoreTone, timeLeft, typeLabel, urgent } from "../src/lib/reacts-format.ts";

const now = Date.parse("2026-11-09T12:00:00Z");
const at = (h: number) => new Date(now + h * 3600_000).toISOString();
const cases: [string, unknown, unknown][] = [
  ["expirou", timeLeft(at(-1), now), "expirou"],
  ["minutos", timeLeft(at(0.5), now), "faltam 30 min"],
  ["horas", timeLeft(at(5), now), "faltam 5 h"],
  ["dias", timeLeft(at(52), now), "faltam 2 d 4 h"],
  ["sem data", timeLeft(null, now), "—"],
  ["urgente", urgent(at(3), now), true],
  ["não urgente", urgent(at(30), now), false],
  ["expirado não é urgente", urgent(at(-2), now), false],
  ["nota alta", scoreTone(86), "alta"],
  ["nota média", scoreTone(50), "media"],
  ["nota baixa", scoreTone(20), "baixa"],
  ["sem nota", scoreTone(null), "sem"],
  ["por mil", perMille(1800, 596078), "3,02"],
  ["por mil sem dados", perMille(0, 100), "—"],
  ["motivo", reasonLabel("angulo_fraco"), "Ângulo fraco"],
  ["tipo", typeLabel("talking_head"), "Talking head"],
  ["tipo vazio", typeLabel(null), "Tipo por classificar"],
  ["link do guião", guiaoHref("numeiro-2026-11-09-57"), "/guioes?date=2026-11-09&open=numeiro-2026-11-09-57"],
  ["sem guião", guiaoHref(null), null],
  ["cdn instagram", allowedVideoUrl("https://scontent-mrs2-1.cdninstagram.com/o1/v/x.mp4?a=1"), true],
  ["cdn fbcdn", allowedVideoUrl("https://instagram.frtm1-1.fna.fbcdn.net/o1/x.mp4"), true],
  ["http recusado", allowedVideoUrl("http://scontent.cdninstagram.com/x.mp4"), false],
  ["host qualquer recusado", allowedVideoUrl("https://evil.example.com/x.mp4"), false],
  ["sufixo falso recusado", allowedVideoUrl("https://cdninstagram.com.evil.io/x.mp4"), false],
  ["nome do ficheiro", downloadName("kiko.ishot", "instagram:DfW7duUNv5g"), "react_kiko.ishot_DfW7duUNv5g.mp4"],
  ["nome sanitizado", downloadName("a/../b", "instagram:x\"y"), "react_a..b_xy.mp4"],
];
let bad = 0;
for (const [name, got, want] of cases) {
  if (got !== want) { bad++; console.error(`FAIL ${name}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`); }
}
console.log(`reacts-format: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
