import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";
import type { NotifChannel, NotifChannelKey, NotifGroup, Suppressed } from "@/lib/notif-format";

/*
 * Notificações por evento (FR-15-05, FR-14-02, flag notifications.prefs, ADR-0040). Tudo por RPCs: o servidor verifica a
 * capacidade (settings.manage para o cliente, acesso ao cliente para as pessoais) e a flag em cada chamada.
 * Só "na app" envia. Email e resumo diário ficam guardados como preferência e aparecem como indisponíveis, com o motivo.
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
export const isForbidden = (e: unknown) => (e as RpcError | null)?.code === "42501";
export const isFlagOff = (e: unknown) => (e as RpcError | null)?.code === "55000";

type EventBase = {
  kind: string; group: NotifGroup; label: string; description: string; recipients: string;
  mandatory: boolean; mandatory_reason: string | null;
};
export type WsChannelState = { channel: NotifChannelKey; enabled: boolean; default: boolean; required: boolean; customized: boolean };
export type WsEvent = EventBase & { channels: WsChannelState[] };
export type WsNotifSettings =
  | { enabled: false; can_manage: boolean }
  | { enabled: true; can_manage: boolean; channels: NotifChannel[]; events: WsEvent[]; suppressed_30d: Suppressed[] | null };

export type MyChannelState = WsChannelState & { allowed: boolean; locked: boolean; mine: boolean; effective: boolean };
export type MyEvent = EventBase & { channels: MyChannelState[] };
export type MyNotifPrefs =
  | { enabled: false }
  | {
      enabled: true; workspace: { id: string; name: string; timezone: string | null }; channels: NotifChannel[]; events: MyEvent[];
      muted: boolean; muted_until: string | null; suppressed_30d: Suppressed[];
    };
export type MyNotifWorkspace = { id: string; name: string; muted: boolean; muted_until: string | null };

export const fetchWsNotif = (ws: string) => rpc<WsNotifSettings>("notif_settings", { p_ws: ws });
export const setWsNotif = (ws: string, kind: string, channel: NotifChannelKey, enabled: boolean, required = false) =>
  rpc<WsNotifSettings>("notif_settings_set", { p_ws: ws, p_kind: kind, p_channel: channel, p_enabled: enabled, p_required: required });

export const fetchMyNotifWorkspaces = () => rpc<MyNotifWorkspace[]>("my_notif_workspaces", {});
export const fetchMyNotif = (ws: string) => rpc<MyNotifPrefs>("my_notif_prefs", { p_ws: ws });
export const setMyNotif = (ws: string, kind: string, channel: NotifChannelKey, enabled: boolean) =>
  rpc<MyNotifPrefs>("my_notif_pref_set", { p_ws: ws, p_kind: kind, p_channel: channel, p_enabled: enabled });
export const setMyMute = (ws: string, muted: boolean, until: string | null) =>
  rpc<MyNotifPrefs>("my_notif_mute", { p_ws: ws, p_muted: muted, p_until: until });
