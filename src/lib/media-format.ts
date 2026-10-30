/* Biblioteca de media (W8, ADR-0038): regras e formatação sem dependências, para testar em node. O servidor é quem decide. */

export type MediaKind = "video" | "audio" | "imagem" | "thumbnail" | "legenda" | "documento" | "link_externo";
export const KIND_LABEL: Record<MediaKind, string> = {
  video: "Vídeo", audio: "Áudio", imagem: "Imagem", thumbnail: "Miniatura", legenda: "Legendas", documento: "Documento", link_externo: "Link externo",
};
export type MediaStatus = "em_trabalho" | "final" | "arquivado";
export const STATUS_LABEL: Record<MediaStatus, string> = { em_trabalho: "Em trabalho", final: "Final", arquivado: "Arquivado" };
export const FORMATS = ["9:16", "16:9", "1:1", "4:5", "outro"] as const;
export const VERSION_STATE_LABEL: Record<string, string> = { pendente: "por concluir", pronta: "pronta", falhou: "falhou", apagada: "apagada" };

/** Extensões que o browser às vezes não reconhece (devolve type vazio). */
const EXT_MIME: Record<string, string> = {
  srt: "application/x-subrip", vtt: "text/vtt", mov: "video/quicktime", mp4: "video/mp4", webm: "video/webm", m4a: "audio/mp4",
  mp3: "audio/mpeg", wav: "audio/wav", aac: "audio/aac", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp",
  gif: "image/gif", pdf: "application/pdf", txt: "text/plain", docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};
export function mimeOf(name: string, type: string): string {
  if (type) return type.toLowerCase();
  const ext = name.toLowerCase().match(/\.([a-z0-9]{1,10})$/)?.[1];
  return (ext && EXT_MIME[ext]) || "";
}

export function kindForMime(mime: string): Exclude<MediaKind, "link_externo"> {
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  if (mime.startsWith("image/")) return "imagem";
  if (mime === "text/vtt" || mime === "application/x-subrip") return "legenda";
  return "documento";
}

/** Mesma regra que _media_kind_mime_ok no SQL. */
export function kindAccepts(kind: MediaKind, mime: string): boolean {
  switch (kind) {
    case "video": return mime.startsWith("video/");
    case "audio": return mime.startsWith("audio/");
    case "imagem": return mime.startsWith("image/");
    case "thumbnail": return ["image/png", "image/jpeg", "image/webp"].includes(mime);
    case "legenda": return ["text/vtt", "application/x-subrip", "text/plain"].includes(mime);
    case "documento": return ["application/pdf", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"].includes(mime);
    default: return false;
  }
}

export type PolicyLike = { allowed_mime: string[]; max_file_bytes: number; quota_bytes: number };
export type UsageLike = { stored_bytes: number; reserved_bytes: number };

/** Verificação antecipada no browser (poupa um envio inútil); o servidor repete tudo. null = pode seguir. */
export function precheck(file: { name: string; size: number; type: string }, policy: PolicyLike, usage: UsageLike, kind?: MediaKind): string | null {
  const mime = mimeOf(file.name, file.type);
  if (file.size <= 0) return "O ficheiro está vazio.";
  if (!mime || !policy.allowed_mime.includes(mime)) return `O tipo ${mime || "desconhecido"} não é permitido neste cliente.`;
  if (kind && !kindAccepts(kind, mime)) return `Um ficheiro ${mime} não serve para ${KIND_LABEL[kind].toLowerCase()}.`;
  if (file.size > policy.max_file_bytes) return `Tem ${bytes(file.size)}; o máximo por ficheiro neste cliente é ${bytes(policy.max_file_bytes)}.`;
  const free = policy.quota_bytes - usage.stored_bytes - usage.reserved_bytes;
  if (file.size > free) return `A quota do cliente não chega: livre ${bytes(Math.max(0, free))}.`;
  return null;
}

export function bytes(n: number | null | undefined): string {
  if (n === null || n === undefined) return "-";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let v = n; let i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  const s = i === 0 ? String(v) : v.toFixed(v < 10 ? 1 : 0);
  return `${s.replace(".", ",")} ${u[i]}`;
}

export const pctOf = (used: number, total: number) => (total > 0 ? Math.min(100, Math.round((used / total) * 100)) : 0);

/** Espera antes da tentativa n (1, 2, 3...): 1 s, 2 s, 4 s... até 15 s, com até 20% de variação. */
export function backoff(attempt: number, rnd = Math.random()): number {
  const base = Math.min(15_000, 1000 * 2 ** Math.max(0, attempt - 1));
  return Math.round(base * (1 + (rnd - 0.5) * 0.4));
}

/** Estado HTTP do envio que vale a pena repetir (rede, tempo, limite, servidor). */
export const retryable = (status: number) => status === 0 || status === 408 || status === 429 || status >= 500;

export function hex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function splitTags(s: string): string[] {
  const out: string[] = [];
  for (const raw of s.split(/[\s,]+/)) {
    const t = raw.replace(/^#+/, "").trim().toLowerCase();
    if (t && !out.includes(t)) out.push(t);
  }
  return out;
}

/** O que dá para pré-visualizar no browser. */
export function previewKind(mime: string | null | undefined): "image" | "video" | "audio" | "pdf" | null {
  if (!mime) return null;
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  if (mime === "application/pdf") return "pdf";
  return null;
}
