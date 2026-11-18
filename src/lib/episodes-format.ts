/**
 * Edição do episódio completo (POD-01..06, CHG-013, ADR-0087): regras puras do formulário e do resultado.
 * O servidor (episode_request) volta a validar tudo; isto só evita pedidos que ele recusaria.
 */
export const EPISODE_FILES = ["master.mp4", "audio.mp3", "legendas.srt", "capitulos.txt", "notas.md", "cortes.json"] as const;
export type EpisodeFile = (typeof EPISODE_FILES)[number];

export const FILE_LABEL: Record<EpisodeFile, string> = {
  "master.mp4": "Vídeo editado (master)", "audio.mp3": "Áudio (MP3)", "legendas.srt": "Legendas (.srt)",
  "capitulos.txt": "Capítulos", "notas.md": "Notas e títulos", "cortes.json": "Lista de cortes",
};

export const CAM_NAME = /^[a-z][a-z0-9_]{0,15}$/;
export type CamRow = { name: string; version: string };

/** Problema do formulário em linguagem simples, ou null se o pedido pode seguir. */
export function camsProblem(rows: CamRow[], audio: string, wide: string): string | null {
  const used = rows.filter((r) => r.version);
  if (used.length === 0) return "Escolhe pelo menos um vídeo.";
  if (used.length > 4) return "No máximo 4 câmaras.";
  const names = used.map((r) => r.name.trim());
  if (names.some((n) => !CAM_NAME.test(n))) return "Nomes das câmaras: letras minúsculas, números e _ (ex.: frente, largo, convidado).";
  if (new Set(names).size !== names.length) return "Duas câmaras com o mesmo nome.";
  if (new Set(used.map((r) => r.version)).size !== used.length) return "O mesmo vídeo em duas câmaras.";
  if (audio && !names.includes(audio)) return "A câmara do som tem de ser uma das escolhidas.";
  if (wide && !names.includes(wide)) return "O plano largo tem de ser uma das câmaras escolhidas.";
  if (wide && used.length === 1) return "Com uma câmara só não há plano largo à parte.";
  return null;
}

export function camsPayload(rows: CamRow[]): Record<string, string> {
  return Object.fromEntries(rows.filter((r) => r.version).map((r) => [r.name.trim(), r.version]));
}

/** Perfil colado (resultado do style-extract ou perfil direto) -> objeto para o pedido; null se vazio; erro se não for JSON. */
export function parseProfile(text: string): { profile: Record<string, unknown> | null; error: string | null } {
  const t = text.trim();
  if (!t) return { profile: null, error: null };
  try {
    const j = JSON.parse(t) as Record<string, unknown>;
    const p = (j && typeof j === "object" && "profile" in j ? j.profile : j) as Record<string, unknown>;
    if (!p || typeof p !== "object" || Array.isArray(p)) return { profile: null, error: "O perfil tem de ser um objeto JSON." };
    return { profile: p, error: null };
  } catch {
    return { profile: null, error: "O perfil não é JSON válido." };
  }
}

export type EpisodeSummary = { before_s?: number; after_s?: number; removed_s?: number; removed_pct?: number; cuts?: number;
  by_reason?: Record<string, number>; warning?: string | null };

export function durText(s: number | null | undefined): string {
  if (s == null || !Number.isFinite(s)) return "—";
  const t = Math.round(s), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), x = t % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(x).padStart(2, "0")}` : `${m}:${String(x).padStart(2, "0")}`;
}

/** Uma linha: "52:10 → 44:03 · 312 cortes · 15,6% removido". */
export function summaryLine(s: EpisodeSummary | null | undefined): string | null {
  if (!s || s.before_s == null || s.after_s == null) return null;
  const pct = s.removed_pct != null ? `${String(s.removed_pct).replace(".", ",")}% removido` : null;
  return [`${durText(s.before_s)} → ${durText(s.after_s)}`, s.cuts != null ? `${s.cuts} cortes` : null, pct].filter(Boolean).join(" · ");
}

/** Motivos ordenados pelo tempo removido: [["pausa acima do máximo", "3:10"], ...]. */
export function reasonRows(s: EpisodeSummary | null | undefined): [string, string][] {
  return Object.entries(s?.by_reason ?? {}).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, durText(v)]);
}
