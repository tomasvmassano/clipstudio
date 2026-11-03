"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/*
 * Interruptores de funcionalidades (MIG-09, ADR-0031). Um módulo novo entra só para o dono da agência e é ligado cliente a
 * cliente em /funcionalidades. Disponibilidade não é autorização (CAP-09): o servidor continua a verificar as capacidades.
 */

export type FlagStage = "off" | "owner" | "agency" | "all";
export const STAGE_LABEL: Record<FlagStage, string> = {
  off: "Desligado", owner: "Só o dono da agência", agency: "Equipa da agência", all: "Todos com acesso",
};
export type FlagDef = {
  key: string; label: string; module: string; scope: "ws" | "org"; default_stage: FlagStage; description: string | null;
  agency_stage: FlagStage | null; clients: Record<string, FlagStage>;
};
export type FlagsAdmin = { flags: FlagDef[]; clients: { id: string; name: string }[] };

const cache = new Map<string, { at: number; p: Promise<string[]> }>();
const listeners = new Set<() => void>();

export function fetchMyFlags(ws: string | null, token: string | null): Promise<string[]> {
  const k = `${ws ?? ""}:${token ? "t" : "u"}`;
  const hit = cache.get(k);
  if (hit && Date.now() - hit.at < 60_000) return hit.p;
  const p = Promise.resolve(supabase().rpc("my_flags", { p_ws: ws, p_token: token }))
    .then(({ data, error }) => { if (error) throw new Error(friendlyError(error.message)); return (data ?? []) as string[]; })
    .catch((e) => { cache.delete(k); throw e; });
  cache.set(k, { at: Date.now(), p });
  return p;
}

/** Flags ligadas para esta pessoa no cliente (ws) ou no espaço da agência (ws nulo). null enquanto carrega. */
export function useFlags(ws: string | null, token: string | null = null, enabled = true): Set<string> | null {
  const [flags, setFlags] = useState<Set<string> | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => { const f = () => setTick((x) => x + 1); listeners.add(f); return () => { listeners.delete(f); }; }, []);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    fetchMyFlags(ws, token).then((l) => { if (alive) setFlags(new Set(l)); }).catch(() => { if (alive) setFlags(new Set()); });   // sem resposta: tudo desligado
    return () => { alive = false; };
  }, [ws, token, enabled, tick]);
  return flags;
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(error.details || friendlyError(error.message));
  return data as T;
}
export const fetchFlagsAdmin = () => rpc<FlagsAdmin>("flags_admin", {});
export async function setFlag(key: string, ws: string | null, stage: FlagStage | null) {
  const r = await rpc<FlagsAdmin>("flag_set", { p_key: key, p_ws: ws, p_stage: stage });
  cache.clear();
  listeners.forEach((f) => f());
  return r;
}
