import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/* Tarefas, handoffs e caixa de entrada (PRD TEAM-06, FR-17-01, FR-17-05; ADR-0007). */

export type TaskStatus = "todo" | "doing" | "blocked" | "done" | "cancelled";
export type TaskKind = "task" | "review" | "recording" | "edit" | "publish" | "request";
export type TaskPriority = "low" | "normal" | "high" | "urgent";
export type Task = {
  id: string; workspace_id: string; title: string; description: string | null; kind: TaskKind; status: TaskStatus; priority: TaskPriority;
  assignee_id: string | null; assignee_email: string | null; assignee_has_access: boolean | null; due_at: string | null; blocked_reason: string | null;
  content: { id: string; n: number; date: string; tema: string | null; editorial_status: string } | null;
  source: { id: number; titulo: string; kind: string } | null;
  rule_id: string | null; created_label: string | null; created_kind: string; created_at: string; completed_at: string | null; lock_version: number;
  deps: { id: string; title: string; status: TaskStatus }[]; open_deps: number; comments: number; overdue: boolean;
  workspace?: string;
};
export type TaskDetail = Task & {
  comments_list: { id: string; author_label: string | null; body: string; created_at: string; mentions: string[] }[];
  history: { action: string; actor_label: string; actor_kind: string; before: Record<string, unknown> | null; after: Record<string, unknown> | null; created_at: string }[];
  can_manage: boolean; can_work: boolean;
};
export type Assignee = { user_id: string; email: string };
export type TaskRule = {
  id: string; on_event: string; complete_on: string[]; kind: TaskKind; title: string; assignee_id: string | null; assignee_email: string | null;
  assignee_has_access: boolean | null; priority: TaskPriority; due_hours: number | null; active: boolean; tasks_open: number;
};
export type Inbox = {
  notifications: { id: string; workspace_id: string; workspace: string; kind: string; entity_type: string; entity_id: string; title: string; body: string | null; read_at: string | null; created_at: string }[];
  tasks: Task[];
  approvals: { id: string; workspace_id: string; workspace: string; n: number; date: string; tema: string | null; hook: string | null; since: string }[];
  unassigned: { id: string; workspace_id: string; workspace: string; title: string; created_at: string }[];
};

export const STATUS_LABEL: Record<TaskStatus, string> = { todo: "Por fazer", doing: "Em curso", blocked: "Bloqueada", done: "Feita", cancelled: "Cancelada" };
export const KIND_LABEL: Record<TaskKind, string> = { task: "Tarefa", review: "Revisão", recording: "Gravação", edit: "Edição", publish: "Publicação", request: "Pedido" };
export const PRIORITY_LABEL: Record<TaskPriority, string> = { low: "Baixa", normal: "Normal", high: "Alta", urgent: "Urgente" };
export const EVENT_LABEL: Record<string, string> = {
  "script.created": "Guião criado", "script.submitted": "Guião enviado para revisão", "script.approved": "Guião aprovado",
  "script.rejected": "Guião rejeitado", "review.changes_requested": "Pedidas alterações ao guião", "recording.confirmed": "Guião marcado como gravado", "production.editing": "Guião passou a edição", "production.ready": "Guião pronto",
  "request.created": "Pedido do talento criado", "source.approved": "Fonte selecionada",
};
export const HISTORY_LABEL: Record<string, string> = {
  "task.created": "criou", "task.updated": "alterou", "task.commented": "comentou", "task.auto_completed": "fechou automaticamente",
  "task.dependency_added": "adicionou dependência", "task.dependency_removed": "removeu dependência",
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export type TaskScope = "open" | "mine" | "unassigned" | "done";
export const fetchTasks = (access: Access, scope: TaskScope, content?: string) =>
  rpc<Task[]>("tasks_list", { p_ws: access.ws, p_scope: scope, p_content: content ?? null, p_token: access.token });
export const fetchTask = (access: Access, id: string) => rpc<TaskDetail>("task_get", { p_id: id, p_token: access.token });
export const fetchAssignees = (access: Access) => rpc<Assignee[]>("tasks_assignees", { p_ws: access.ws, p_token: access.token });
export const createTask = (access: Access, f: Record<string, unknown>) => rpc<Task>("task_create", { p_ws: access.ws, p_fields: f, p_token: access.token });
export const updateTask = (access: Access, id: string, patch: Record<string, unknown>, lock?: number) =>
  rpc<Task>("task_update", { p_id: id, p_patch: patch, p_lock: lock ?? null, p_token: access.token });
export const dependTask = (access: Access, id: string, on: string, link: boolean) =>
  rpc<Task>("task_depend", { p_id: id, p_on: on, p_link: link, p_token: access.token });
export const commentTask = (access: Access, id: string, body: string, mentions: string[]) =>
  rpc<TaskDetail>("task_comment", { p_id: id, p_body: body, p_mentions: mentions, p_token: access.token });
export const fetchRules = (access: Access) => rpc<TaskRule[]>("task_rules_list", { p_ws: access.ws });
export const saveRule = (access: Access, r: Record<string, unknown>) => rpc<TaskRule>("task_rule_save", { p_ws: access.ws, p_rule: r });
export const fetchInbox = () => rpc<Inbox>("inbox", {});
export const markRead = (ids: string[] | null) => rpc<number>("notifications_read", { p_ids: ids });

/** "dd/mm hh:mm" no fuso do workspace. */
export function fmtDue(iso: string | null, tz = "Asia/Dubai") {
  if (!iso) return "";
  return new Intl.DateTimeFormat("pt-PT", { timeZone: tz, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}
/** valor para <input type="datetime-local"> no fuso do workspace, e de volta para ISO UTC. */
export function toLocalInput(iso: string | null, tz = "Asia/Dubai") {
  if (!iso) return "";
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function fromLocalInput(v: string, tz = "Asia/Dubai"): string | null {
  if (!v) return null;
  // trata o valor como hora local do workspace: calcula o desvio desse fuso nessa data
  const asUtc = new Date(v + ":00Z");
  const local = new Date(toLocalInput(asUtc.toISOString(), tz) + ":00Z");
  return new Date(asUtc.getTime() - (local.getTime() - asUtc.getTime())).toISOString();
}

// ---------- templates, checklist e carga (W3-03) ----------
export type TemplateItem = { title: string; kind: TaskKind; priority: TaskPriority; offset_days: number; hour: number; assignee_id: string | null;
  depends_on: number[]; assignee_email?: string | null; assignee_has_access?: boolean | null };
export type Template = { id: string; workspace_id: string; name: string; description: string | null; items: TemplateItem[]; checklist: string[]; active: boolean; applied: number };
export type ChecklistItem = { id: string; label: string; done: boolean; done_label: string | null; done_at: string | null; from_template: boolean };
export type Workload = {
  wip_limit: number | null; unassigned: number;
  people: { user_id: string; email: string; has_access: boolean; open: number; doing: number; blocked: number; overdue: number; due_7d: number; done_7d: number; over_limit: boolean }[];
};
export const fetchTemplates = (access: Access) => rpc<Template[]>("templates_list", { p_ws: access.ws, p_token: access.token });
export const saveTemplate = (access: Access, t: Record<string, unknown>) => rpc<Template>("template_save", { p_ws: access.ws, p_tpl: t });
export const cloneTemplate = (id: string, target: string) => rpc<Template>("template_clone", { p_tpl: id, p_target_ws: target });
export const applyTemplate = (access: Access, id: string, content: string) =>
  rpc<{ tasks_created: number; tasks: number; checklist: ChecklistItem[] }>("template_apply", { p_tpl: id, p_content: content, p_token: access.token });
export const fetchChecklist = (access: Access, content: string) => rpc<ChecklistItem[]>("checklist_list", { p_content: content, p_token: access.token });
export const addChecklist = (access: Access, content: string, label: string) => rpc<ChecklistItem[]>("checklist_add", { p_content: content, p_label: label, p_token: access.token });
export const toggleChecklist = (access: Access, id: string, done: boolean) => rpc<ChecklistItem[]>("checklist_toggle", { p_item: id, p_done: done, p_token: access.token });
export const fetchWorkload = (access: Access) => rpc<Workload>("workload", { p_ws: access.ws, p_token: access.token });
export const setWipLimit = (access: Access, limit: number | null) => rpc<Workload>("workload_set_limit", { p_ws: access.ws, p_limit: limit });
