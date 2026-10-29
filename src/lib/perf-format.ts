/* Centro de desempenho (PRD §40, ADR-0033): rótulos e formatação sem dependências, para testar em node. */

export type Age = "1h" | "24h" | "72h" | "7d" | "30d";
export const AGES: Age[] = ["1h", "24h", "72h", "7d", "30d"];
export const AGE_LABEL: Record<Age, string> = { "1h": "1 h", "24h": "24 h", "72h": "72 h", "7d": "7 dias", "30d": "30 dias" };

export type Dimension =
  | "account" | "platform" | "creator" | "tier" | "content" | "hook" | "style" | "theme" | "format" | "persona" | "generation" | "origin";
export const DIMENSION_LABEL: Record<Dimension, string> = {
  account: "Conta", platform: "Plataforma", creator: "Criador ou marca", tier: "Camada", content: "Conteúdo (mesma peça em várias contas)",
  hook: "Mecanismo do hook", style: "Estilo de edição", theme: "Tema", format: "Formato", persona: "Frase-persona", generation: "Geração", origin: "Origem",
};
export const LEVER_LABEL: Record<string, string> = {
  format: "Formato", theme: "Tema", hook: "Mecanismo do hook", style: "Estilo de edição", persona: "Frase-persona", generation: "Geração",
  platform: "Plataforma", tier: "Camada", hour: "Hora local", duration: "Duração",
};
export const TIER_LABEL: Record<string, string> = { A: "A · principal", B: "B · clips oficial", C: "C · trial", D: "D · parceiro" };
export const HEALTH_LABEL: Record<string, string> = {
  sem_registo: "Sem registo", normal: "Normal", alcance_reduzido: "Alcance reduzido", restrita: "Restrita", suspensa: "Suspensa",
};
export const MECHANISM_LABEL: Record<string, string> = {
  contra: "Contra", numero: "Número", ego: "Ego", confissao: "Confissão", segredo: "Segredo", pergunta: "Pergunta",
};
export const INFERENCE_LABEL: Record<string, string> = {
  publicacoes: "ligada a um guião", motor: "correspondência do motor pela transcrição", analise: "análise do motor", nenhuma: "sem ligação",
};
export const UNAVAILABLE = "Indisponível até ligar a conta pela API oficial";
export const INSUFFICIENT = "Amostra insuficiente";

const PT = "pt-PT";

/** Índice normalizado: "2,0×". Nulo nunca vira zero. */
export function fmtIdx(v: number | string | null | undefined): string {
  if (v === null || v === undefined || v === "") return "";
  const n = typeof v === "string" ? Number(v) : v;
  if (!Number.isFinite(n)) return "";
  return `${new Intl.NumberFormat(PT, { minimumFractionDigits: 1, maximumFractionDigits: 2 }).format(n)}×`;
}

/** Tom do índice: acima de 1,5 forte, abaixo de 0,5 fraco (só cor de apoio, o número diz tudo). */
export function idxTone(v: number | string | null | undefined): "strong" | "normal" | "weak" | "none" {
  if (v === null || v === undefined || v === "") return "none";
  const n = Number(v);
  if (!Number.isFinite(n)) return "none";
  return n >= 1.5 ? "strong" : n < 0.5 ? "weak" : "normal";
}

export function fmtPct(v: number | string | null | undefined): string {
  if (v === null || v === undefined || v === "") return "";
  const n = Number(v);
  return Number.isFinite(n) ? new Intl.NumberFormat(PT, { style: "percent", maximumFractionDigits: 0 }).format(n) : "";
}

export function fmtPerK(v: number | string | null | undefined): string {
  if (v === null || v === undefined || v === "") return "";
  const n = Number(v);
  return Number.isFinite(n) ? new Intl.NumberFormat(PT, { maximumFractionDigits: 1 }).format(n) : "";
}

/** Explica porque um índice não existe (fotografia em falta ou base curta). */
export function idxMissingReason(snap: { views: number | null; base_n: number | null } | undefined, minBase: number): string {
  if (!snap) return "Sem leitura nessa idade";
  if ((snap.base_n ?? 0) < minBase) return `${INSUFFICIENT} (${snap.base_n ?? 0} de ${minBase} na base)`;
  return "Sem índice";
}

export function dateTime(iso: string | null | undefined, tz: string): string {
  if (!iso) return "";
  return new Date(iso).toLocaleString(PT, { timeZone: tz, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}
