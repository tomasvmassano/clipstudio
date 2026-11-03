import { parseMoment, fmtMoment, driveFileId, driveLinks } from "../src/lib/media-time.ts";
const id = "1AbCdEfGhIjKlMnOpQrStUvWx";
const cases: [string, unknown, unknown][] = [
  ["0:23", parseMoment("0:23"), 23000], ["23", parseMoment("23"), 23000], ["23s", parseMoment("23s"), 23000], ["1:02:03", parseMoment("1:02:03"), 3723000],
  ["12.5", parseMoment("12.5"), 12500], ["vazio", parseMoment(" "), null], ["0:61", parseMoment("0:61"), null], ["abc", parseMoment("abc"), null],
  ["fmt 23s", fmtMoment(23400), "0:23"], ["fmt 1h", fmtMoment(3723000), "1:02:03"],
  ["link view", driveFileId(`https://drive.google.com/file/d/${id}/view?usp=sharing`), id], ["link open", driveFileId(`https://drive.google.com/open?id=${id}`), id],
  ["só id", driveFileId(id), id], ["outro site", driveFileId("https://example.com/x.mp4"), null], ["curto", driveFileId("abc"), null],
  ["view com tempo", driveLinks(id, 23900).view, `https://drive.google.com/file/d/${id}/view?t=23`], ["preview", driveLinks(id).preview, `https://drive.google.com/file/d/${id}/preview`],
];
let bad = 0; for (const [n, g, e] of cases) if (g !== e) { bad++; console.log("FAIL", n, JSON.stringify(g), "≠", JSON.stringify(e)); }
console.log(`media-time ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
