import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Discover, Reference } from "@/lib/types";

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
