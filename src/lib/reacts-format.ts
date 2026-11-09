/* Radar de reacts (W10-25, REACT-02..05): formatação pura, testável sem browser. */

export type ReactAi = {
  score?: number; risk_level?: "baixo" | "medio" | "alto"; risk_flags?: string[]; angulo?: string; resumo?: string; resposta?: string;
  hooks?: { text: string; mecanismo?: string }[];
  parts?: Partial<Record<"polemica" | "persona" | "contra_angulo" | "frescura" | "alvo" | "risco", number>>;
  porque?: string; model?: string; prompt_version?: string; agent_version?: string; evaluated_at?: string;
};

export const REJECT_REASONS: { value: string; label: string }[] = [
  { value: "sem_interesse", label: "Sem interesse" },
  { value: "velho", label: "Já é velho" },
  { value: "alvo_errado", label: "Alvo errado" },
  { value: "angulo_fraco", label: "Ângulo fraco" },
  { value: "risco", label: "Risco" },
  { value: "outro", label: "Outro" },
];
export const reasonLabel = (v: string | null | undefined) => REJECT_REASONS.find((r) => r.value === v)?.label ?? "—";

const TYPES: Record<string, string> = { react: "React", talking_head: "Talking head", visual: "Visual", frase: "Frase", outro: "Outro" };
export const typeLabel = (v: string | null | undefined) => (v ? TYPES[v] ?? v : "Tipo por classificar");

export const PART_LABELS: Record<string, string> = {
  polemica: "Polémica", persona: "Encaixe na persona", contra_angulo: "Contra-ângulo", frescura: "Frescura", alvo: "Tamanho do alvo", risco: "Risco (mais = mais seguro)",
};

/** Tempo até expirar a janela do react: "faltam 2 d 4 h", "faltam 5 h", "faltam 40 min", "expirou". */
export function timeLeft(expiresAt: string | null | undefined, now = Date.now()): string {
  if (!expiresAt) return "—";
  const ms = new Date(expiresAt).getTime() - now;
  if (!Number.isFinite(ms)) return "—";
  if (ms <= 0) return "expirou";
  const min = Math.floor(ms / 60000);
  if (min < 60) return `faltam ${Math.max(min, 1)} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `faltam ${h} h`;
  return `faltam ${Math.floor(h / 24)} d ${h % 24} h`;
}

/** Urgência para cor: menos de 12 h é urgente. */
export const urgent = (expiresAt: string | null | undefined, now = Date.now()) =>
  !!expiresAt && new Date(expiresAt).getTime() - now > 0 && new Date(expiresAt).getTime() - now < 12 * 3600_000;

export const scoreTone = (s: number | null | undefined): "alta" | "media" | "baixa" | "sem" =>
  s == null ? "sem" : s >= 75 ? "alta" : s >= 50 ? "media" : "baixa";

/** Comentários por mil reproduções, com 2 casas. */
export function perMille(comments: number | null | undefined, views: number | null | undefined): string {
  if (!comments || !views) return "—";
  return (comments / views * 1000).toFixed(2).replace(".", ",");
}

/** Link para o guião criado: /guioes?date=AAAA-MM-DD&open=<id> (o id traz a data). */
export function guiaoHref(contentId: string | null | undefined): string | null {
  if (!contentId) return null;
  const m = contentId.match(/(\d{4}-\d{2}-\d{2})-\d+$/);
  return m ? `/guioes?date=${m[1]}&open=${encodeURIComponent(contentId)}` : `/guioes?open=${encodeURIComponent(contentId)}`;
}

/** Só se faz proxy de vídeos dos CDNs das plataformas (evita a rota servir de proxy aberto). */
const HOSTS = [/\.cdninstagram\.com$/i, /\.fbcdn\.net$/i, /\.tiktokcdn\.com$/i, /\.tiktokcdn-us\.com$/i, /\.tiktokv\.com$/i, /\.tiktokcdn-eu\.com$/i];
export function allowedVideoUrl(u: string | null | undefined): boolean {
  if (!u) return false;
  try {
    const x = new URL(u);
    return x.protocol === "https:" && HOSTS.some((h) => h.test(x.hostname));
  } catch { return false; }
}

/** Nome do ficheiro para descarregar: react_<autor>_<id>.mp4, só com caracteres seguros. */
export function downloadName(author: string | null | undefined, refKey: string): string {
  const a = (author ?? "video").replace(/[^A-Za-z0-9._-]/g, "").slice(0, 40) || "video";
  const k = refKey.split(":")[1]?.replace(/[^A-Za-z0-9_-]/g, "") ?? "x";
  return `react_${a}_${k}.mp4`;
}
