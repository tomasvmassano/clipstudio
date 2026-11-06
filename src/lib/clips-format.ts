/** Utilitários puros dos cortes de vídeos longos (Clip Miner, CLIP-01..07, ADR-0063). Testados em tests/clips-format.test.mts. */

export type ClipMeta = {
  score: number; start: string; end: string; hook?: string; title: string; hooks?: string[]; thesis?: string; machine?: string; theme?: string;
  polemic?: string[]; enemy?: { kind: string; target: string } | null; identity_trigger?: string | null; risks?: string[]; persons?: string[];
  context?: string | null; justification?: string; reordered?: boolean; times?: { in: number; out: number; duration: number };
  model?: string; prompt_version?: string; speakers?: string;
};

export const POLEMIC_LABEL: Record<string, string> = {
  inimigo: "inimigo", gatilho_identidade: "gatilho de identidade", tensao: "tensão", afirmacao_forte: "afirmação forte",
  numero: "número", confissao: "confissão",
};

/** Segundos em m:ss (ou h:mm:ss). */
export function clipTime(sec: number | null | undefined): string {
  if (sec == null || !Number.isFinite(sec) || sec < 0) return "—";
  const s = Math.floor(sec), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${r}` : `${m}:${r}`;
}

/** Etiquetas de polémica em texto (as desconhecidas ficam de fora). Lista vazia = "não polémico". */
export function polemicText(tags: string[] | null | undefined): string {
  const xs = (tags ?? []).map((t) => POLEMIC_LABEL[t]).filter(Boolean);
  return xs.length ? xs.join(", ") : "não polémico";
}

type AssetLike = { tags: string[]; current: { id: string; state: string; storage?: string; mime: string | null; media_info?: { duration?: number } | null } | null };

/** Vídeos que podem ser fonte de cortes: no R2, prontos, de vídeo, com 2 min ou mais (ou duração desconhecida), que não sejam
 * eles próprios cortes, saídas de pacotes ou exports. O servidor volta a verificar tudo. */
export function clipMasters<T extends AssetLike>(assets: T[]): T[] {
  return assets.filter((a) => {
    const v = a.current;
    if (!v || v.storage !== "r2" || v.state !== "pronta" || !(v.mime ?? "").startsWith("video/")) return false;
    if (a.tags.includes("corte") || a.tags.includes("pacote")) return false;
    const d = v.media_info?.duration;
    return d == null || (d >= 120 && d <= 4 * 3600);
  });
}

/** Pontuação em texto com o aviso de que ordena, não prevê (CLIP-03). */
export function scoreText(score: number | null | undefined): string {
  return score == null || !Number.isFinite(score) ? "—" : `${Math.round(score)}/100`;
}
