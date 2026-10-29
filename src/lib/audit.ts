import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/* Histórico de ações por cliente (audit_events, só leitura; ADR-0015). */

export type AuditRow = {
  id: number; at: string; action: string; actor_kind: string; actor: string | null; entity_type: string | null; entity_id: string | null;
  before: Record<string, unknown> | null; after: Record<string, unknown> | null; result: string | null;
};
export type AuditPage = { rows: AuditRow[]; next_before: number | null; actors: { id: string; label: string | null }[]; actions: string[] };

export const ACTION_LABEL: Record<string, string> = {
  "workspace.created": "criou o cliente", "workspace.updated": "mudou as definições", "workspace.archived": "arquivou o cliente", "workspace.restored": "recuperou o cliente",
  "member.updated": "mudou um membro", "member.removed": "removeu um membro", "member.assigned": "atribuiu alguém da agência",
  "invitation.create": "convidou", "invitation.revoked": "cancelou um convite", "invitation.accepted": "aceitou o convite",
  "grant.set": "deu uma exceção de permissão", "grant.revoked": "retirou uma exceção de permissão",
  "script.update": "editou um guião", "script.submitted": "enviou um guião para revisão", "script.approved": "aprovou um guião",
  "script.rejected": "rejeitou um guião", "script.reopened": "reabriu um guião", "script.approval": "mudou a aprovação de um guião",
  "script.rescheduled": "mudou o dia de um guião", "review.changes_requested": "pediu alterações num guião",
  "brief.saved": "guardou um brief", "content.source_linked": "ligou uma fonte a um guião", "content.source_unlinked": "desligou uma fonte de um guião",
  "reference.linked": "ligou uma referência", "request.created": "fez um pedido de tema",
  "recording.session_opened": "abriu o teleprompter", "recording.queue_set": "mudou a fila de gravação", "recording.confirmed": "confirmou uma gravação",
  "take.recorded": "registou um take", "take.update": "mudou um take",
  "production.scheduled": "agendou a produção", "production.not_started": "tirou da agenda",
  "task.created": "criou uma tarefa", "task.updated": "mudou uma tarefa", "template.cloned": "copiou um template", "workload.limit_set": "mudou o limite de tarefas",
};

/** Sem etiqueta própria: "script.qualquer_coisa" vira "script · qualquer coisa". */
export const actionLabel = (a: string) => ACTION_LABEL[a] ?? a.replace(".", " · ").replaceAll("_", " ");

const show = (v: unknown) => (v == null ? "—" : typeof v === "object" ? JSON.stringify(v) : String(v));

/** Campos que mudaram entre o antes e o depois (ou só o depois, quando é uma criação). */
export function changes(before: Record<string, unknown> | null, after: Record<string, unknown> | null) {
  const keys = [...new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})])];
  return keys
    .filter((k) => show(before?.[k]) !== show(after?.[k]))
    .map((k) => ({ key: k, before: before ? show(before[k]) : "", after: show(after?.[k]).slice(0, 400) }));
}

export async function fetchAudit(ws: string, f: { action: string | null; actor: string | null; from: string | null; to: string | null; before: number | null }) {
  const { data, error } = await supabase().rpc("audit_list", {
    p_ws: ws, p_action: f.action, p_actor: f.actor, p_from: f.from, p_to: f.to, p_before: f.before, p_limit: 50,
  });
  if (error) throw new Error(friendlyError(error.message));
  return data as AuditPage;
}
