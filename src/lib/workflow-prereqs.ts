import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Prereqs } from "@/lib/editorial-format";
export { prereqGrid, type Prereqs, type PrereqRule } from "@/lib/editorial-format";

/* Pré-requisitos configuráveis das transições de produção (FR-17-05, ADR-0047). O servidor verifica sempre em content_production. */

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(error.details || friendlyError(error.message));
  return data as T;
}

export const fetchPrereqs = (a: Access) => rpc<Prereqs>("workflow_prereqs", { p_ws: a.ws, p_content: null, p_token: a.token });
export const setPrereq = (a: Access, transition: string, requirement: string, enabled: boolean) =>
  rpc<Prereqs>("workflow_prereq_set", { p_ws: a.ws, p_transition: transition, p_requirement: requirement, p_enabled: enabled, p_token: a.token });
