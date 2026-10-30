/* Centro de integrações (W8, ADR-0039): nomes dos estados e formatação sem dependências, para testar em node. */

export type IntegHealth = "ok" | "aviso" | "indisponivel";

/** Estado devolvido pelo servidor → texto em PT-PT. Estado desconhecido aparece tal como vem (nunca escondido). */
export const STATE_LABEL: Record<string, string> = {
  por_ligar: "Por ligar",
  ligada: "Ligada",
  a_expirar: "A expirar",
  expirada: "Expirada",
  revogada: "Revogada",
  parcial: "Parcialmente ligada",
  sem_contas: "Sem contas",
  em_dia: "Em dia",
  atrasada: "Atrasada",
  sem_dados: "Sem dados",
  ativo: "Ativo",
  parado: "Sem contacto",
  por_alojar: "Por alojar",
};
export const stateLabel = (s: string | null | undefined) => (s ? STATE_LABEL[s] ?? s : "Desconhecido");

export const OUTCOME_LABEL: Record<string, string> = { ok: "Passou", aviso: "Passou com avisos", falhou: "Falhou", sem_dados: "Sem dados" };

export const JOB_STATUS_LABEL: Record<string, string> = {
  queued: "na fila", running: "a correr", succeeded: "concluída", failed: "falhou", cancelled: "cancelada", dead: "desistiu",
};

/** Há quanto tempo, em PT-PT ("há 5 min", "há 3 h", "há 2 dias"). Sem data: "nunca". */
export function ago(iso: string | null | undefined, now: number = Date.now()): string {
  if (!iso) return "nunca";
  const s = Math.round((now - new Date(iso).getTime()) / 1000);
  if (Number.isNaN(s)) return "nunca";
  if (s < 0) return "agora";
  if (s < 60) return "há menos de 1 min";
  const m = Math.floor(s / 60);
  if (m < 60) return `há ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 48) return `há ${h} h`;
  return `há ${Math.floor(h / 24)} dias`;
}

/** Dias até a validade do token (negativo = passou). */
export function daysUntil(iso: string | null | undefined, now: number = Date.now()): number | null {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return null;
  return Math.floor((t - now) / 86_400_000);
}

export function expiryText(iso: string | null | undefined, now: number = Date.now()): string {
  const d = daysUntil(iso, now);
  if (d === null) return "sem validade registada";
  if (d < 0) return "o token já expirou";
  if (d === 0) return "expira hoje";
  return d === 1 ? "expira amanhã" : `expira em ${d} dias`;
}

export const HEALTH_CLASS: Record<IntegHealth, string> = {
  ok: "text-emerald-500",
  aviso: "text-amber-500",
  indisponivel: "text-muted-foreground",
};

/** Motivo de revogação válido (o servidor volta a verificar). */
export const reasonOk = (r: string) => r.trim().length >= 3 && r.trim().length <= 500;
