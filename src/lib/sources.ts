import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { BriefFields, ContentContext, Guiao, Source, SourceStatus } from "@/lib/types";

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string; raw?: string };
    e.code = error.code;
    e.raw = error.message;
    throw e;
  }
  return data as T;
}

export type SourceFilter = { status?: SourceStatus | null; kind?: "source" | "talent_request" | null; q?: string | null };

export const fetchSources = (access: Access, f: SourceFilter = {}, limit = 200) =>
  rpc<Source[]>("sources_list", { p_ws: access.ws, p_status: f.status ?? null, p_kind: f.kind ?? null, p_q: f.q?.trim() || null, p_limit: limit, p_token: access.token });

export type NewSource = { titulo: string; fonte_url?: string; fonte?: string; fonte_tipo?: string; categoria?: string; resumo?: string; tags?: string[] };
export const createSource = (access: Access, f: NewSource) => rpc<Source>("source_create", { p_ws: access.ws, p_fields: f, p_token: access.token });

/** Id da fonte que já existe quando o servidor recusa por URL repetido (PT409 "duplicado:<id>"). */
export const duplicateOf = (e: unknown): number | null => {
  const raw = (e as { raw?: string }).raw ?? "";
  const m = /^duplicado:(\d+)/.exec(raw);
  return m ? Number(m[1]) : null;
};

export const updateSource = (access: Access, id: number, patch: Record<string, unknown>) =>
  rpc<Source>("source_update", { p_id: id, p_patch: patch, p_token: access.token });

export const createRequest = (access: Access, text: string) => rpc<Source>("talent_request_create", { p_ws: access.ws, p_text: text, p_token: access.token });

export const sourceToScript = (access: Access, id: number, date?: string) =>
  rpc<Guiao>("source_to_script", { p_source: id, p_date: date ?? null, p_token: access.token });

export const fetchContext = (access: Access, contentId: string) => rpc<ContentContext>("content_context", { p_content: contentId, p_token: access.token });

export const saveBrief = (access: Access, contentId: string, f: BriefFields) =>
  rpc<ContentContext>("brief_save", { p_content: contentId, p_fields: f, p_token: access.token });

export const linkSource = (access: Access, contentId: string, sourceId: number, link: boolean) =>
  rpc<ContentContext>("content_link_source", { p_content: contentId, p_source: sourceId, p_link: link, p_token: access.token });
