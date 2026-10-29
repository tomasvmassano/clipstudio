import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

/* Campanhas e séries, responsável, plataformas e etiquetas do guião (W2-07, FR-02-03). ADR-0029. */

export type Project = { id: string; name: string; kind: "campanha" | "serie"; status: "ativa" | "arquivada"; starts_on: string | null; ends_on: string | null; scripts: number };
export type ProjectList = { can_manage: boolean; projects: Project[] };
export type Owner = { user_id: string; email: string; label: string };
export type MetaPatch = Partial<{ project_id: string | null; owner_id: string | null; tags: string[]; platforms: string[] }>;

export const PLATFORMS = [
  { v: "instagram", l: "Instagram" }, { v: "tiktok", l: "TikTok" }, { v: "youtube", l: "YouTube" },
] as const;
export const KIND_LABEL: Record<Project["kind"], string> = { campanha: "Campanha", serie: "Série" };

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

// As listas mudam pouco e cada cartão de guião precisa delas: um pedido por cliente, partilhado, renovado a cada minuto.
const cache = new Map<string, { at: number; p: Promise<unknown> }>();
function cached<T>(key: string, f: () => Promise<T>): Promise<T> {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < 60_000) return hit.p as Promise<T>;
  const p = f().catch((e) => { cache.delete(key); throw e; });
  cache.set(key, { at: Date.now(), p });
  return p;
}
const forget = (ws: string) => { for (const k of cache.keys()) if (k.startsWith(`${ws}:`)) cache.delete(k); };
// quem mostra nomes de campanhas (cartões, teleprompter) é avisado quando a lista muda
const listeners = new Set<() => void>();
export function onProjectsChanged(cb: () => void) { listeners.add(cb); return () => { listeners.delete(cb); }; }

export const fetchProjects = (a: Access, fresh = false) => {
  if (fresh) forget(a.ws);
  return cached(`${a.ws}:projects`, () => rpc<ProjectList>("projects_list", { p_ws: a.ws, p_token: a.token }));
};
export const fetchOwners = (a: Access) => cached(`${a.ws}:owners`, () => rpc<Owner[]>("content_owners", { p_ws: a.ws, p_token: a.token }));
export async function saveProject(a: Access, id: string | null, fields: Partial<Pick<Project, "name" | "kind" | "status" | "starts_on" | "ends_on">>) {
  const r = await rpc<ProjectList>("project_save", { p_ws: a.ws, p_id: id, p_fields: fields, p_token: a.token });
  forget(a.ws);
  cache.set(`${a.ws}:projects`, { at: Date.now(), p: Promise.resolve(r) });
  listeners.forEach((f) => f());
  return r;
}
export async function setContentMeta(a: Access, id: string, patch: MetaPatch) {
  const g = await rpc<Guiao>("content_meta_set", { p_id: id, p_patch: patch, p_token: a.token });
  cache.delete(`${a.ws}:projects`);   // contagem de guiões por campanha
  return g;
}

/** Etiquetas como a pessoa as escreve: separadas por vírgula; o servidor normaliza (minúsculas, sem repetidas). */
export const parseTags = (s: string) => Array.from(new Set(s.split(",").map((x) => x.trim().toLowerCase()).filter(Boolean)));
