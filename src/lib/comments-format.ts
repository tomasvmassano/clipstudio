/* Comentários como fonte de ideias (W10-26, REACT-08): formatação pura, testável sem browser. */

export type CommentKind = "discorda" | "concorda" | "outro_angulo" | "pergunta";
export type CommentAi = {
  score?: number; risk_level?: "baixo" | "medio" | "alto"; risk_flags?: string[]; ideia?: string; angulo?: string; resposta?: string; porque?: string;
  hooks?: { text: string; mecanismo?: string }[];
  parts?: Partial<Record<"potencial" | "persona" | "tensao" | "alcance" | "frescura" | "risco", number>>;
  model?: string; prompt_version?: string; evaluated_at?: string;
};

export const KINDS: { value: CommentKind; label: string; hint: string }[] = [
  { value: "discorda", label: "Discorda", hint: "Responder com um vídeo a defender a nossa posição" },
  { value: "concorda", label: "Concorda e acrescenta", hint: "Pegar no que acrescentou e ir mais longe" },
  { value: "outro_angulo", label: "Outro ponto de vista", hint: "Argumentar contra ou a favor do ângulo novo" },
  { value: "pergunta", label: "Pergunta", hint: "Uma dúvida que dá um vídeo inteiro" },
];
export const kindLabel = (v: string | null | undefined) => KINDS.find((k) => k.value === v)?.label ?? "Por classificar";

export const COMMENT_REJECT_REASONS: { value: string; label: string }[] = [
  { value: "sem_interesse", label: "Sem interesse" },
  { value: "repetido", label: "Já respondemos" },
  { value: "fraco", label: "Pouco a dizer" },
  { value: "pessoal", label: "Ataque pessoal" },
  { value: "risco", label: "Risco" },
  { value: "outro", label: "Outro" },
];
export const commentReasonLabel = (v: string | null | undefined) => COMMENT_REJECT_REASONS.find((r) => r.value === v)?.label ?? "—";

export const COMMENT_PART_LABELS: Record<string, string> = {
  potencial: "Potencial de vídeo", persona: "Encaixe na mensagem", tensao: "Tensão / debate", alcance: "Gostos e respostas",
  frescura: "Frescura", risco: "Risco (mais = mais seguro)",
};

/** Link do reel onde o comentário foi feito, ou null se não for um link https. */
export function reelLink(u: string | null | undefined): string | null {
  if (!u) return null;
  try { return new URL(u).protocol === "https:" ? u : null; } catch { return null; }
}

/** Resumo de envolvimento: "120 gostos · 14 respostas". */
export function engagement(likes: number | null | undefined, replies: number | null | undefined): string {
  const p: string[] = [];
  if (likes != null) p.push(`${likes} ${likes === 1 ? "gosto" : "gostos"}`);
  if (replies != null) p.push(`${replies} ${replies === 1 ? "resposta" : "respostas"}`);
  return p.join(" · ");
}

/** Próxima corrida do agente (a cada 3 dias) a partir da última; null se nunca correu. */
export function nextRun(lastRun: string | null | undefined, everyDays = 3): Date | null {
  if (!lastRun) return null;
  const t = new Date(lastRun).getTime();
  return Number.isFinite(t) ? new Date(t + everyDays * 86400_000) : null;
}
