"use client";

import { useCallback, useEffect, useState } from "react";
import { fetchGuioes, subscribeGuioes, updateGuiao } from "@/lib/data";
import type { Access } from "@/lib/access";
import type { Guiao, GuiaoPatch } from "@/lib/types";
import { useSession } from "@/components/session-provider";

/** O que o utilizador pode fazer aos guiões neste workspace (o servidor volta a verificar cada ação). */
export type ScriptCaps = { approve: boolean; reject: boolean; edit: boolean; record: boolean; export: boolean };

/** Guiões de um dia (mais os de dias anteriores por gravar), ao vivo. */
export function useGuioes(access: Access, date: string) {
  const [all, setAll] = useState<Guiao[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const { can } = useSession();

  const reload = useCallback(async () => {
    try {
      setAll(await fetchGuioes(access, date));
      setError("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [access, date]);

  useEffect(() => {
    let alive = true;
    fetchGuioes(access, date)
      .then((x) => { if (alive) { setAll(x); setError(""); } })
      .catch((e: Error) => { if (alive) setError(e.message); })
      .finally(() => { if (alive) setLoading(false); });
    const unsub = subscribeGuioes(access, reload);
    return () => { alive = false; unsub(); };
  }, [access, date, reload]);

  const patch = useCallback(
    async (id: string, p: GuiaoPatch) => {
      const g = await updateGuiao(access, id, p);
      setAll((prev) => prev.map((x) => (x.id === id ? g : x)));
      return g;
    },
    [access]
  );

  const caps: ScriptCaps = {
    approve: can("scripts.approve"),
    reject: can("scripts.reject"),
    edit: can("scripts.edit"),
    record: can("recording.confirm"),
    export: can("scripts.export"),
  };
  const canWrite = caps.approve || caps.reject || caps.edit || caps.record;

  return { all, loading, error, reload, patch, caps, canWrite };
}
