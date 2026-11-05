/*
 * Regras puras do fluxo editorial (sem rede), partilhadas pela UI e pelos testes unitários (tests/editorial-format.test.mts):
 * aprovar gravados em lote (W9-02), confirmação de eliminar (W9-01), calendário (W9-03) e pré-requisitos (W9-04). ADR-0047.
 */

// ---------- aprovar gravados (W9-02) ----------
export type PendingItem = {
  id: string; n: number; date: string; tema: string | null; hook: string | null;
  editorial_status: string; production_status: string; legacy_status: string | null; lock_version: number; recorded_at: string | null;
  recorded_version_no: number | null; current_version_no: number | null; same_as_recorded: boolean;
};
export type PendingApproval = { items: PendingItem[]; can: { submit: boolean; bulk: boolean } };

/** Os que se podem aprovar já em lote: texto igual ao gravado (e, se estiverem em rascunho, quem aprova também submete). */
export const approvable = (it: PendingItem, can: PendingApproval["can"]) =>
  it.same_as_recorded && (it.editorial_status === "in_review" || can.submit);

/** Porque não entra no lote (texto para a pessoa). */
export function blockedReason(it: PendingItem, can: PendingApproval["can"]): string | null {
  if (!it.same_as_recorded) {
    return it.recorded_version_no == null
      ? "Não há registo da versão gravada: abre o guião e aprova-o à mão."
      : `O texto mudou depois de gravado (gravada a v${it.recorded_version_no}): abre o guião e decide à mão.`;
  }
  if (it.editorial_status !== "in_review" && !can.submit) return "Está em rascunho e não podes submeter: pede a quem o escreveu.";
  return null;
}

// ---------- eliminar (W9-01) ----------
/** A palavra que a pessoa escreve para confirmar (a UI manda depois o ID do guião ao servidor). */
export const CONFIRM_WORD = "eliminar";
export const confirmOk = (typed: string) => typed.trim().toLowerCase() === CONFIRM_WORD;

// ---------- pré-requisitos das transições (W9-04) ----------
export type PrereqCatalog = {
  transitions: { key: string; label: string; to: string }[];
  requirements: { key: string; label: string; applies: string[] }[];
};
export type PrereqRule = { transition: string; requirement: string; enabled: boolean };
export type Prereqs = { catalog: PrereqCatalog; rules: PrereqRule[]; can: { manage: boolean } };

/** Grelha transição × condição: null onde a condição não se aplica (a UI deriva do catálogo do servidor). */
export function prereqGrid(p: Prereqs): { transition: PrereqCatalog["transitions"][number]; cells: (PrereqRule | null)[] }[] {
  return p.catalog.transitions.map((t) => ({
    transition: t,
    cells: p.catalog.requirements.map((r) => (r.applies.includes(t.key)
      ? p.rules.find((x) => x.transition === t.key && x.requirement === r.key) ?? { transition: t.key, requirement: r.key, enabled: false }
      : null)),
  }));
}

/** Texto a mostrar quando o servidor recusa uma transição por pré-requisito: o detalhe (causa + próximo responsável). */
export function prereqMessage(message: string, details: string | null | undefined): string | null {
  return message.includes("pre_requisito_em_falta") ? (details || "Falta um pré-requisito desta transição. Vê as regras em Definições.") : null;
}
