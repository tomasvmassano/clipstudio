import { backoff, bytes, kindAccepts, kindForMime, mimeOf, precheck, previewKind, retryable, splitTags } from "../src/lib/media-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
const pol = { allowed_mime: ["video/mp4", "image/png", "application/x-subrip"], max_file_bytes: 50 * 1048576, quota_bytes: 100 * 1048576 };
const use = { stored_bytes: 60 * 1048576, reserved_bytes: 10 * 1048576 };
eq("mime: .srt sem type do browser", mimeOf("legendas.SRT", ""), "application/x-subrip");
eq("mime: type do browser ganha", mimeOf("a.bin", "Video/MP4"), "video/mp4");
eq("tipo por mime", [kindForMime("video/mp4"), kindForMime("audio/mpeg"), kindForMime("image/png"), kindForMime("text/vtt"), kindForMime("application/pdf")],
  ["video", "audio", "imagem", "legenda", "documento"]);
eq("miniatura não aceita gif", kindAccepts("thumbnail", "image/gif"), false);
eq("link externo não aceita ficheiros", kindAccepts("link_externo", "video/mp4"), false);
eq("precheck ok", precheck({ name: "a.mp4", size: 1000, type: "video/mp4" }, pol, use), null);
eq("precheck vazio", precheck({ name: "a.mp4", size: 0, type: "video/mp4" }, pol, use), "O ficheiro está vazio.");
eq("precheck tipo", precheck({ name: "a.zip", size: 10, type: "application/zip" }, pol, use), "O tipo application/zip não é permitido neste cliente.");
eq("precheck grande", precheck({ name: "a.mp4", size: 51 * 1048576, type: "video/mp4" }, pol, use)?.startsWith("Tem 51 MB"), true);
eq("precheck quota com reservas", precheck({ name: "a.mp4", size: 31 * 1048576, type: "video/mp4" }, pol, use), "A quota do cliente não chega: livre 30 MB.");
eq("precheck tipo do ativo", precheck({ name: "a.png", size: 10, type: "image/png" }, pol, use, "video"), "Um ficheiro image/png não serve para vídeo.");
eq("bytes", [bytes(512), bytes(1536), bytes(52428800), bytes(5368709120)], ["512 B", "1,5 KB", "50 MB", "5,0 GB"]);
eq("backoff 1,2,3 sem variação", [backoff(1, 0.5), backoff(2, 0.5), backoff(3, 0.5), backoff(10, 0.5)], [1000, 2000, 4000, 15000]);
eq("backoff com variação limitada", backoff(1, 1) <= 1200 && backoff(1, 0) >= 800, true);
eq("repetir rede/5xx/429, não 4xx", [retryable(0), retryable(503), retryable(429), retryable(400), retryable(403)], [true, true, true, false, false]);
eq("etiquetas", splitTags("#Dubai, final  dubai"), ["dubai", "final"]);
eq("pré-visualização", [previewKind("application/pdf"), previewKind("text/vtt"), previewKind("video/quicktime")], ["pdf", null, "video"]);
console.log(`media-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
