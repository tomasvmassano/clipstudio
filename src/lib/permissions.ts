import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/* Consola de permissões por cliente (PRD CAP-02, CAP-03, CAP-05; ADR-0014). O servidor decide; isto só mostra e pede. */

export type Capability = { key: string; label: string; module: string; risk: "A" | "M" | "B"; status: string; mine?: boolean };
export type PermMember = {
  user_id: string; email: string; role: string; affiliation: "agency_staff" | "client_staff"; status: string; job_title: string | null;
  effective: string[]; can_edit: boolean;
};
export type Grant = { id: number; user_id: string; capability: string; effect: "allow" | "deny"; expires_at: string | null; reason: string | null; created_at: string; by: string | null };
export type Matrix = { capabilities: Capability[]; roles: Record<string, string[]>; members: PermMember[]; grants: Grant[] };
export type Explain = { allowed: boolean; source?: "role" | "grant" | "deny" | "agency_owner"; grant_id?: number; reasons: string[]; capability?: string };

/** Disponível hoje? (as outras capacidades existem no registo mas o módulo ainda não chegou.) */
export const isLive = (c: Capability) => c.status === "ativo" || c.status === "legado" || c.status.startsWith("ativo");

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchMatrix = (ws: string) => rpc<Matrix>("permissions_matrix", { p_ws: ws });
export const explainAccess = (ws: string, user: string, cap: string) => rpc<Explain>("access_explain", { p_ws: ws, p_user: user, p_cap: cap });
export async function setGrant(ws: string, user: string, cap: string, effect: "allow" | "deny", expiresAt: string | null, reason: string) {
  const { data, error } = await supabase().rpc("grant_set", { p_ws: ws, p_user: user, p_cap: cap, p_effect: effect, p_expires_at: expiresAt, p_reason: reason });
  if (error) throw new Error(error.message.includes("prazo_invalido") ? "O prazo tem de ser no futuro e no máximo daqui a um ano." : friendlyError(error.message));
  return data as { id: number; now: Explain };
}
export const revokeGrant = (id: number, reason: string) => rpc<{ now: Explain }>("grant_revoke", { p_id: id, p_reason: reason });
export const fetchCapabilityLabels = () => rpc<Record<string, { label: string; module: string }>>("capability_labels", {});

/** "Ver como" (CAP-05, BIZ-07): só leitura, avaliado no servidor e auditado. */
export type Simulation = {
  target: { kind: "user" | "role"; label: string; role: string | null; status: string | null };
  capabilities: (Explain & { key: string; label: string; module: string; status: string })[];
};
export const simulateAccess = (ws: string, target: { user?: string; role?: string }) =>
  rpc<Simulation>("access_simulate", { p_ws: ws, p_user: target.user ?? null, p_role: target.role ?? null });
