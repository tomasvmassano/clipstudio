/* Calendário de publicações (PRD §42, VAR-01; ADR-0036): regras puras sem dependências, para testar em node.
 * O servidor decide (pub_save, pub_approve); isto só avisa enquanto se escreve. */

export type Platform = "instagram" | "tiktok" | "youtube";
export const PLATFORMS: Platform[] = ["instagram", "tiktok", "youtube"];
export const PLATFORM_LABEL: Record<Platform, string> = { instagram: "Instagram", tiktok: "TikTok", youtube: "YouTube" };
export const PLATFORM_SHORT: Record<Platform, string> = { instagram: "IG", tiktok: "TT", youtube: "YT" };

export type ElementKey = "segment" | "title_thesis" | "context_asset" | "narration" | "structure";
export const ELEMENT_KEYS: ElementKey[] = ["segment", "title_thesis", "context_asset", "narration", "structure"];
export const ELEMENT_LABEL: Record<ElementKey, string> = {
  segment: "Segmento", title_thesis: "Tese do título", context_asset: "Ativo de contexto", narration: "Narração ou comentário", structure: "Estrutura",
};
export const ELEMENT_HINT: Record<ElementKey, string> = {
  segment: "Outro excerto do vídeo (ex.: 00:40-01:10).",
  title_thesis: "Outra afirmação no título, não só outras palavras.",
  context_asset: "Outra imagem ou vídeo de prova. Só conta com tese nova.",
  narration: "Voz ou comentário novo por cima.",
  structure: "Outra ordem ou forma (ex.: top 3, pergunta e resposta).",
};
export type Elements = Partial<Record<ElementKey, string>>;

const norm = (s: string | undefined | null) => {
  const x = (s ?? "").replace(/\s+/g, " ").trim().toLowerCase();
  return x === "" ? null : x;
};

/** VAR-01: quantos dos 5 elementos diferem ({} = o original). Ativo de contexto sem tese nova conta zero. */
export function variantDiff(a: Elements, b: Elements): number {
  const d = (k: ElementKey) => norm(a[k]) !== norm(b[k]);
  let n = 0;
  if (d("segment")) n++;
  if (d("title_thesis")) n++;
  if (d("context_asset") && d("title_thesis")) n++;
  if (d("narration")) n++;
  if (d("structure")) n++;
  return n;
}
export const countsAsNew = (e: Elements) => variantDiff(e, {}) >= 2;

/** Limpa os elementos: tira vazios e espaços (igual ao servidor). */
export function cleanElements(e: Elements): Elements {
  const out: Elements = {};
  for (const k of ELEMENT_KEYS) { const v = (e[k] ?? "").trim(); if (v) out[k] = v; }
  return out;
}

/** Hashtags como o servidor as guarda: com #, sem espaços nem repetidos. Devolve também as inválidas. */
export function parseHashtags(text: string): { tags: string[]; invalid: string[] } {
  const tags: string[] = []; const invalid: string[] = [];
  for (const raw of text.split(/[\s,]+/)) {
    if (!raw) continue;
    const t = raw.startsWith("#") ? raw : `#${raw}`;
    if (!/^#[^\s#]{1,100}$/.test(t)) { invalid.push(raw); continue; }
    if (!tags.includes(t)) tags.push(t);
  }
  return { tags, invalid };
}

export type PubStatus = "planeada" | "aprovada" | "cancelada";
export const STATUS_LABEL: Record<PubStatus, string> = { planeada: "Por aprovar", aprovada: "Aprovada", cancelada: "Cancelada" };
export type PolicyRequired = "qualquer" | "agencia" | "cliente" | "ambos";
export const POLICY_LABEL: Record<PolicyRequired, string> = {
  qualquer: "Qualquer pessoa com a capacidade", agencia: "Agência (direção criativa)", cliente: "Cliente", ambos: "Agência e cliente",
};
export const SIDE_LABEL: Record<string, string> = { agencia: "agência", cliente: "cliente", qualquer: "qualquer pessoa com a capacidade" };
export const BLOCKED_LABEL: Record<string, string> = {
  sem_capacidade: "Não tens a capacidade de aprovar este tipo de publicação.",
  autoaprovacao: "Neste cliente quem planeou ou mudou a publicação não a pode aprovar.",
  ja_aprovaste: "Já aprovaste esta revisão.",
  parte_errada: "A aprovação que falta é da outra parte.",
  versao_por_aprovar: "A versão do guião não é a aprovada.",
  conflito: "Há um conflito que bloqueia (vê abaixo).",
  hora_passada: "A hora já passou. Muda a hora.",
};
export const WINDOW_LABEL: Record<string, string> = { rolling_24h: "24 h móveis", calendar_day: "por dia" };
export const SCOPE_LABEL: Record<string, string> = { conta: "por conta", projeto: "por projeto (todos os clientes)" };
export const CONNECTION_LABEL: Record<string, string> = { por_ligar: "Por ligar", ligada: "Ligada", expirada: "Expirada", revogada: "Revogada" };
export const PUBLISH_UNAVAILABLE = "Publicação automática chega quando as plataformas aprovarem a app.";

/** Mesmo dia noutra hora: dado um instante e um dia novo (YYYY-MM-DD), mantém a hora local. */
export function moveToDay(localDateTime: string, day: string) {
  return `${day}T${localDateTime.slice(11, 16)}`;
}
