import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

/*
 * Aprendizagem contínua (PRD §46.2, ADR-0069): motivo em cada edição (LRN-01), lições propostas pelo Editor de lições
 * (LRN-02) e aprovação em versões imutáveis (LRN-03), nos níveis cliente e agência (LRN-04). Tudo por RPCs: o servidor
 * verifica capacidade, flag e cliente em cada chamada.
 */

type RpcError = Error & { code?: string };
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as RpcError;
    e.code = error.code;
    throw e;
  }
  return data as T;
}

// ---------- LRN-01 ----------
export type EditGroup = "hook" | "corpo" | "cta" | "facto" | "tom" | "outro";
export const GROUP_LABEL: Record<EditGroup, string> = { hook: "Hook", corpo: "Corpo", cta: "CTA", facto: "Factos", tom: "Tom e voz", outro: "Outro" };
export type EditCode = { code: string; label: string; group: EditGroup; source: "lrn" | "rework" };
export type EditOptions = { enabled: boolean; threshold: number; codes: EditCode[] };
export type EditRatio = {
  engine: boolean; ratio: number | null; required: boolean; threshold?: number;
  edits?: { codes: string[]; note: string | null; at: string }[];
};

export const fetchEditOptions = (a: Access) => rpc<EditOptions>("lrn_edit_options", { p_ws: a.ws, p_token: a.token });
export const fetchEditRatio = (a: Access, id: string) => rpc<EditRatio>("content_edit_ratio", { p_id: id, p_token: a.token });
export const saveEditReason = (a: Access, id: string, codes: string[], note: string) =>
  rpc<{ recorded: boolean; signal_id?: string; ratio: number }>("content_edit_reason", { p_id: id, p_codes: codes, p_note: note || null, p_token: a.token });
export type Decision = "approved" | "changes_requested" | "rejected";
export const decideLearned = (a: Access, id: string, to: Decision, o: { codes?: string[]; note?: string; reason?: string; reasonCode?: string; lock?: number }) =>
  rpc<Guiao>("content_decide_learned", {
    p_id: id, p_to: to, p_codes: o.codes ?? [], p_note: o.note || null, p_reason: o.reason || null, p_reason_code: o.reasonCode || null,
    p_lock: o.lock ?? null, p_token: a.token,
  });

/** Percentagem inteira para mostrar ("42%"). */
export const pctRatio = (r: number | null | undefined) => (r == null ? "—" : `${Math.round(r * 100)}%`);

// ---------- LRN-02/03/04 ----------
export type LessonCategory = EditGroup;
export type LessonExample = { signal_id: string; content_id: string; kind: string; edit_ratio: number; before: string; after: string | null; note: string | null };
export type Lesson = {
  id: string; level: "client" | "agency"; status: "proposed" | "approved" | "rejected"; category: LessonCategory; text: string; proposed_text: string;
  edited: boolean; rationale: string | null; source: "engine" | "promoted"; proposed_at: string; decided_at: string | null; decided_label: string | null;
  decision_note: string | null;
  evidence: { edits?: number; content_ids?: string[]; codes?: Record<string, number>; examples?: LessonExample[]; window?: { since: string; until: string } };
};
export type LessonVersion = {
  id: string; version_no: number; active: boolean; lessons: { id: string; category: LessonCategory; text: string }[];
  change: { action: "approve" | "retire" | "restore"; lesson_id?: string; from_version?: number; note?: string | null };
  created_label: string | null; created_at: string;
};
export type LessonVersionRow = Omit<LessonVersion, "lessons"> & { n: number };
export type LessonJob = { id: string; status: string; created_at: string; finished_at: string | null; last_error: string | null; result: Record<string, unknown> | null };
export type LessonsPage = {
  can: { approve: boolean; agency: boolean };
  proposed: Lesson[]; decided: Lesson[]; active: LessonVersion | null; versions: LessonVersionRow[];
  signals: { since: string; edits: number; no_reason: number; unedited: number; rejected: number };
  job: LessonJob | null;
  /**
   * Equipa da agência: regras em vigor e propostas. Equipa do cliente: só as regras em vigor, só leitura, com categoria e
   * texto (readonly = true; sem change nem created_label; ADR-0071). Código de equipa: null.
   */
  agency: { readonly?: boolean; active: (Omit<LessonVersion, "change" | "created_label" | "created_at"> & Partial<Pick<LessonVersion, "change" | "created_label" | "created_at">>) | null; proposed: Lesson[] } | null;
};

export const fetchLessons = (a: Access) => rpc<LessonsPage>("lrn_lessons_list", { p_ws: a.ws, p_token: a.token });
export const decideLesson = (a: Access, id: string, action: "approve" | "reject", text?: string, note?: string) =>
  rpc<Lesson>("lrn_lesson_decide", { p_id: id, p_action: action, p_text: text || null, p_note: note || null, p_token: a.token });
export const retireLesson = (a: Access, id: string, note?: string) => rpc<LessonVersion>("lrn_lesson_retire", { p_id: id, p_note: note || null, p_token: a.token });
export const restoreLessonVersion = (a: Access, id: string) => rpc<LessonVersion>("lrn_version_restore", { p_version: id, p_token: a.token });
export const promoteLesson = (a: Access, id: string, text?: string) => rpc<Lesson>("lrn_lesson_promote", { p_id: id, p_text: text || null, p_token: a.token });
export const runLessonEditor = (a: Access) => rpc<LessonJob>("lrn_lessons_run", { p_ws: a.ws, p_token: a.token });

export const JOB_LABEL: Record<string, string> = {
  queued: "na fila", running: "a correr", succeeded: "concluída", failed: "falhou", dead: "falhou de vez", cancelled: "cancelada",
};
