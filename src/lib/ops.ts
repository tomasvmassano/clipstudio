import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import { realtime } from "@/lib/realtime";

/*
 * Minha área de trabalho e quem trabalha em quê (PRD FR-01-03, FR-17-01, OPS-02, OPS-03, OPS-04, OPS-10; ADR-0034).
 * O servidor decide tudo: o que entra na fila, quem pode ver/adiar/passar e quem aparece nos cartões.
 */

export type QueueCategory = "task" | "approval" | "recording" | "decision" | "mention" | "alert" | "info";
export type QueueItem = {
  key: string; workspace_id: string; workspace: string; kind: QueueCategory; categories: QueueCategory[]; reasons: string[];
  title: string; detail: string | null; href: string; due_at: string | null; day: string | null; priority: "low" | "normal" | "high" | "urgent";
  overdue: boolean; last_at: string; unread: number; notification_ids: string[]; only_notifications: boolean; seen: boolean;
  acknowledged_at: string | null; snoozed_until: string | null; rev: string;
  task: { id: string; status: "todo" | "doing" | "blocked"; lock_version: number; open_deps: number; mine: boolean } | null;
  enabled: boolean;
  can: { ack: boolean; snooze: boolean; delegate: boolean; complete: boolean; start: boolean };
};
export type Queue = {
  items: QueueItem[]; snoozed: QueueItem[]; enabled: string[];
  counts: Record<QueueCategory | "all" | "new" | "snoozed", number>;
};

export type Availability = "available" | "busy" | "away" | "dnd";
export type Member = {
  user_id: string; label: string; email: string; affiliation: "agency_staff" | "client_staff"; role: string; job_title: string | null;
  is_me: boolean; online: boolean; active: boolean; availability: Availability | null; availability_until: string | null;
  working: boolean; open: number; blocked: number; overdue: number; next_due: string | null; last_update: string | null;
  current: { id: string; title: string; due_at: string | null; since: string;
             content: { id: string; n: number; tema: string | null; date: string; project: string | null } | null } | null;
  blocked_tasks: { id: string; title: string; reason: string | null }[];
};
export type TeamPresence = {
  online_window_s: number; active_window_s: number; members: Member[];
  counts: { members: number; online: number; active: number; available: number; busy: number; away: number; working: number; blocked: number };
  me: { member: boolean; status: Availability | null; until: string | null; share_activity: boolean };
};

export const CATEGORY_LABEL: Record<QueueCategory, string> = {
  task: "Tarefa", approval: "Aprovação", recording: "Gravação", decision: "Decisão", mention: "Menção", alert: "Alerta", info: "Aviso",
};
export const CATEGORY_PLURAL: Record<QueueCategory, string> = {
  task: "Tarefas", approval: "Aprovações", recording: "Gravações de hoje", decision: "Decisões", mention: "Menções", alert: "Alertas", info: "Avisos",
};
export const REASON_LABEL: Record<string, string> = {
  assigned: "atribuída a ti", blocked: "bloqueada", changes_requested: "alterações pedidas", approval: "à tua espera para aprovar",
  recording: "gravar hoje", unassigned: "sem responsável", blocked_other: "bloqueada", talent_request: "pedido por decidir",
  overdue: "atrasada", task_mention: "mencionaram-te", script_mention: "mencionaram-te", script_comment: "resposta a comentário",
  automation_error: "erro de automação", task_blocked: "bloqueio", task_done: "concluída", task_assigned: "atribuída",
  task_auto: "criada automaticamente", task_unassigned: "passou para outra pessoa", script_assigned: "ficaste responsável",
  task_delegated: "passaram-ta",
};
export const AVAILABILITY_LABEL: Record<Availability, string> = {
  available: "Disponível", busy: "Ocupado", away: "Ausente", dnd: "Não incomodar",
};

type RpcError = Error & { code?: string };
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || opsError(error.message)) as RpcError;
    e.code = error.code;
    throw e;
  }
  return data as T;
}

function opsError(msg: string) {
  if (msg.includes("item_nao_encontrado")) return "Este item já não está na tua caixa. Atualiza a lista.";
  if (msg.includes("funcionalidade_desligada")) return "Esta funcionalidade ainda não está ligada neste cliente.";
  if (msg.includes("responsavel_sem_acesso")) return "Essa pessoa não pode trabalhar tarefas neste cliente.";
  if (msg.includes("tarefa_fechada")) return "Esta tarefa já está fechada.";
  if (msg.includes("dependencias_abertas")) return "Esta tarefa ainda depende de outras por fechar.";
  if (msg.includes("Failed to fetch") || msg.includes("NetworkError")) return "Sem ligação ao servidor. Verifica a internet e tenta de novo.";
  return friendlyError(msg);
}

export const fetchMyQueue = (ws: string | null) => rpc<Queue>("my_queue", { p_ws: ws });
export const actOnItem = (key: string, action: "ack" | "snooze" | "unsnooze", until?: string) =>
  rpc<{ key: string; changed: boolean }>("inbox_item_act", { p_key: key, p_action: action, p_until: until ?? null });
export const delegateTask = (task: string, to: string, note: string | null, lock?: number) =>
  rpc<{ changed: boolean }>("task_delegate", { p_task: task, p_to: to, p_note: note, p_lock: lock ?? null });
export const fetchTeamPresence = (ws: string) => rpc<TeamPresence>("team_presence", { p_ws: ws });
export const pingPresence = (ws: string, active: boolean) => rpc<{ ok: boolean }>("presence_ping", { p_ws: ws, p_active: active });
export const setAvailability = (patch: { status?: Availability | null; until?: string | null; share_activity?: boolean }) =>
  rpc<{ changed: boolean }>("availability_set", { p_patch: patch });

/** Aviso do canal privado presence:<ws> (RLS exige ops.presence). Só diz "mudou"; os dados vêm de team_presence. */
export function subscribePresence(access: Access, onChange: () => void): (() => void) | null {
  if (access.token) return null;
  return realtime.listen("presence:" + access.ws, async (name, emit) => {
    const sb = supabase();
    await sb.realtime.setAuth();
    return sb.channel(name, { config: { private: true } })
      .on("broadcast", { event: "presence_changed" }, (m) => emit(m.payload))
      .subscribe();
  }, () => onChange());
}

/** Opções de adiamento no fuso do cliente: 1 h, 3 h, amanhã 9:00, segunda 9:00. */
export function snoozeOptions(tz: string, now = new Date()): { label: string; until: string }[] {
  const at9 = (addDays: number) => {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(now).map((x) => [x.type, x.value]));
    // 09:00 local desse dia: calcula o desvio do fuso
    const localMidnightUtc = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day) + addDays, 9, 0);
    const offset = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), Number(p.hour), Number(p.minute)) - Math.floor(now.getTime() / 60000) * 60000;
    return new Date(localMidnightUtc - offset).toISOString();
  };
  const weekday = new Intl.DateTimeFormat("en-GB", { timeZone: tz, weekday: "short" }).format(now);
  const toMonday = ({ Mon: 7, Tue: 6, Wed: 5, Thu: 4, Fri: 3, Sat: 2, Sun: 1 } as Record<string, number>)[weekday] ?? 7;
  const inMin = (m: number) => new Date(Math.ceil((now.getTime() + m * 60000) / 60000) * 60000).toISOString();
  return [
    { label: "Daqui a 1 hora", until: inMin(60) },
    { label: "Daqui a 3 horas", until: inMin(180) },
    { label: "Amanhã às 9:00", until: at9(1) },
    { label: "Segunda às 9:00", until: at9(toMonday) },
  ];
}

export function fmtWhen(iso: string | null, tz: string) {
  if (!iso) return "";
  return new Intl.DateTimeFormat("pt-PT", { timeZone: tz, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

export function fmtAgo(iso: string | null, now = Date.now()) {
  if (!iso) return "sem atualizações";
  const m = Math.max(0, Math.round((now - new Date(iso).getTime()) / 60000));
  if (m < 1) return "agora mesmo";
  if (m < 60) return `há ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.round(h / 24);
  return `há ${d} dia${d > 1 ? "s" : ""}`;
}
