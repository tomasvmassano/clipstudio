import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Discover, RefJobStatus, Reference } from "@/lib/types";

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string; raw?: string };
    e.code = error.code; e.raw = error.message;
    throw e;
  }
  return data as T;
}

export type RefFilter = { q?: string; tag?: string; colecao?: string; favoritos?: boolean; archived?: boolean };
export const fetchReferences = (access: Access, f: RefFilter = {}) =>
  rpc<Reference[]>("references_list", {
    p_ws: access.ws, p_q: f.q?.trim() || null, p_tag: f.tag || null, p_colecao: f.colecao || null,
    p_favoritos: !!f.favoritos, p_archived: !!f.archived, p_token: access.token,
  });
export const fetchDiscover = (access: Access, account?: string) =>
  rpc<Discover>("references_discover", { p_ws: access.ws, p_account: account || null, p_limit: 60, p_token: access.token });
export const createReference = (access: Access, f: Record<string, unknown>) => rpc<Reference>("reference_create", { p_ws: access.ws, p_fields: f, p_token: access.token });
export const updateReference = (access: Access, id: number, patch: Record<string, unknown>) =>
  rpc<Reference>("reference_update", { p_id: id, p_patch: patch, p_token: access.token });
export const linkReference = (access: Access, id: number, target: { content?: string; source?: number }, link: boolean) =>
  rpc<Reference>("reference_link", { p_reference: id, p_content: target.content ?? null, p_source: target.source ?? null, p_link: link, p_token: access.token });

/* ───────────── REF-01..04 (W10-04, ADR-0059): colar link, dissecção, 3 guiões ───────────── */

export type RefJob = {
  id: string; kind: "reference_analysis" | "reference_scripts"; status: RefJobStatus; attempts: number; max_attempts: number;
  created_at: string; started_at: string | null; finished_at: string | null; next_attempt_at: string | null;
  progress: Record<string, unknown> | null; last_error: string | null; requested_label: string | null; result: Record<string, unknown> | null;
};
export type Dissection = {
  hook?: { texto?: string; mecanismo?: string; segundos?: number };
  maquina?: string; maquina_porque?: string; tese?: string; inimigo?: string;
  estrutura?: { inicio_s?: number; fim_s?: number; parte: string; resumo?: string }[];
  duracao_s?: number; palavras_por_segundo?: number; ritmo?: string; porque_funciona?: string; idioma?: string;
  afirmacoes_terceiros?: { texto: string; pessoa?: string; tipo?: string }[];
};
export type RefAnalysisFull = {
  version: number; created_at: string; transcript: string; transcript_source: "scraper" | "manual";
  metrics: { views?: number; likes?: number; comments?: number; shares?: number; duration_s?: number; owner?: string; collected_at?: string;
             source: "scraper"; author_median_views?: number; author_sample?: number; index?: number } | null;
  dissection: Dissection; third_party_flags: number; model: string; prompt_version: string; agent_version: string;
};
export type RefDetail = {
  reference: Reference; analysis: RefAnalysisFull | null;
  versions: { version: number; created_at: string; model: string; prompt_version: string; transcript_source: string }[];
  analysis_job: RefJob | null; scripts_job: RefJob | null;
  scripts: { content_id: string; date: string; n: number; tema: string | null; editorial_status: string; similarity: number | null; analysis_version: number; created_at: string }[];
  worker_ready: boolean; can: { analyze: boolean; adapt: boolean };
};
export type PasteResult = { created: boolean; duplicate: boolean; reference: Reference; job?: RefJob | null };

export const pasteReference = (access: Access, url: string, analyze: boolean) =>
  rpc<PasteResult>("reference_paste", { p_ws: access.ws, p_url: url, p_analyze: analyze, p_token: access.token });
export const analyzeReference = (access: Access, id: number, transcript?: string) =>
  rpc<{ job: RefJob }>("reference_analyze", { p_ref: id, p_transcript: transcript?.trim() || null, p_token: access.token });
export const adaptReference = (access: Access, id: number) => rpc<{ job: RefJob }>("reference_adapt", { p_ref: id, p_token: access.token });
export const fetchReferenceDetail = (access: Access, id: number, version?: number) =>
  rpc<RefDetail>("reference_analysis_get", { p_ref: id, p_version: version ?? null, p_token: access.token });
