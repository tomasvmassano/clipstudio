import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/* Clientes da agência (PRD §2, §3, CAP-08, SCALE-07; ADR-0012). O servidor decide quem vê e faz o quê. */

export type ClientRow = {
  id: string; name: string; handle: string | null; timezone: string; currency: string; status: "active" | "archived";
  created_at: string; members: number; invites: number; can_edit: boolean; agent_config: "draft" | "active" | "retired" | null;
};
export type ClientsList = {
  can: { create: boolean; archive: boolean; assign_agency: boolean };
  clients: ClientRow[];
  agency_staff: { user_id: string; email: string; role: string }[] | null;
};

/** Fusos mais usados primeiro; qualquer fuso IANA é aceite pelo servidor. */
export const TIMEZONES = ["Asia/Dubai", "Europe/Lisbon", "Europe/London", "Europe/Madrid", "Europe/Paris", "America/Sao_Paulo", "America/New_York", "UTC"];
export const CURRENCIES = ["EUR", "AED", "USD", "GBP", "BRL"];

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchClients = () => rpc<ClientsList>("workspaces_list", {});
export const createClient = (v: { name: string; handle: string; timezone: string; currency: string; copyFrom: string | null }) =>
  rpc<{ id: string; name: string; copied: { agentes?: boolean; templates?: number; automacoes?: number } }>("workspace_create", {
    p_name: v.name.trim(), p_handle: v.handle.trim() || null, p_timezone: v.timezone, p_currency: v.currency, p_copy_from: v.copyFrom,
  });
export type ClientPatch = Partial<{ name: string; handle: string; timezone: string; currency: string; require_approval_to_record: boolean;
  logo_path: string | null; brand_color: string | null }>;
export const updateClient = (ws: string, patch: ClientPatch) => rpc<ClientRow & { logo_path: string | null; brand_color: string | null }>("workspace_update", { p_ws: ws, p_patch: patch });

export type Settings = {
  id: string; name: string; handle: string | null; timezone: string; currency: string; logo_path: string | null; brand_color: string | null;
  require_approval_to_record: boolean; wip_limit: number | null; created_at: string; agent_config: "draft" | "active" | "retired" | null;
  counts: { templates: number; automacoes: number };
  can: { manage: boolean; tasks: boolean; agents: boolean; archive: boolean };
};
export const fetchSettings = (ws: string) => rpc<Settings>("workspace_settings", { p_ws: ws });
export const archiveClient = (ws: string, reason: string) => rpc<{ status: string; jobs_cancelled: number }>("workspace_archive", { p_ws: ws, p_reason: reason });
export const restoreClient = (ws: string) => rpc<{ status: string }>("workspace_restore", { p_ws: ws });
