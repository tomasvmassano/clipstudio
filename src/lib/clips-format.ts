/** Utilitários puros dos cortes de vídeos longos (Clip Miner, CLIP-01..07, ADR-0063). Testados em tests/clips-format.test.mts. */

export type ClipMeta = {
  score: number; start: string; end: string; hook?: string; title: string; hooks?: string[]; thesis?: string; machine?: string; theme?: string;
  polemic?: string[]; enemy?: { kind: string; target: string } | null; identity_trigger?: string | null; risks?: string[]; persons?: string[];
  context?: string | null; justification?: string; reordered?: boolean; times?: { in: number; out: number; duration: number };
  model?: string; prompt_version?: string; speakers?: string;
  /** CHG-012: tipo de momento, modo (leve = só legendas) e idioma detetado. */
  moment?: string; mode?: "leve" | "completo"; language?: string | null;
};

/* CHG-012 (W10-45): tipos de momento, link do YouTube e ligação ao ficheiro. */
export const MOMENT_LABEL: Record<string, string> = {
  conversa: "Conversa", reflexao: "Reflexão", opiniao: "Opinião sobre um facto", historia: "História", humor: "Momento engraçado",
  conselho: "Conselho prático", resposta: "Resposta a uma pergunta", confissao: "Confissão", frase: "Frase citável", revelacao: "Revelação",
  outro: "Outro",
};
export const momentText = (m: string | null | undefined) => (m ? MOMENT_LABEL[m] ?? m : "—");

/** Id do vídeo (11 caracteres) de um link do YouTube, ou null. Igual a _youtube_id no servidor. */
export function youtubeId(url: string): string | null {
  const m = /^(?:https?:\/\/)?(?:www\.|m\.|music\.)?(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|shorts\/|live\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})(?:[?&#/].*)?$/.exec(url.trim());
  return m ? m[1] : null;
}

const norm = (t: string) => t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\.[a-z0-9]{2,4}$/, "").replace(/[^a-z0-9]+/g, " ").trim();
const STOP = new Set(["the", "a", "o", "os", "as", "de", "do", "da", "e", "and", "of", "to", "in", "em", "um", "uma", "com", "with", "ep", "episode", "episodio", "final", "mp4", "mov", "v1", "v2"]);
const tokens = (t: string) => new Set(norm(t).split(" ").filter((w) => w.length > 1 && !STOP.has(w)));

/** Quanto um nome de ficheiro/título se parece com o título do vídeo do YouTube (0 a 1, Jaccard das palavras). */
export function titleSimilarity(a: string, b: string): number {
  const x = tokens(a), y = tokens(b);
  if (!x.size || !y.size) return 0;
  let inter = 0;
  for (const w of x) if (y.has(w)) inter += 1;
  return inter / (x.size + y.size - inter);
}

/** O ficheiro mais parecido com o título do YouTube, se for parecido o bastante (≥ 0,34); senão null. */
export function bestMasterMatch<T extends { title: string; current: { original_name: string | null } | null }>(ytTitle: string, masters: T[]): T | null {
  let best: T | null = null, score = 0;
  for (const m of masters) {
    const s = Math.max(titleSimilarity(ytTitle, m.title), titleSimilarity(ytTitle, m.current?.original_name ?? ""));
    if (s > score) { score = s; best = m; }
  }
  return score >= 0.34 ? best : null;
}

/** Cortes automáticos pela duração: ~1 por 4 min, entre 5 e 20 (igual ao servidor e ao motor). */
export const autoClipCount = (sec: number | null | undefined) => (!sec ? 8 : Math.max(5, Math.min(20, Math.round(sec / 240))));

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
