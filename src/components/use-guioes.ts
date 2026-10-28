"use client";

import { useCallback, useEffect, useState } from "react";
import { fetchGuioes, subscribeGuioes, updateGuiao } from "@/lib/data";
import { DEFAULT_CLIENT } from "@/lib/supabase";
import type { Guiao, GuiaoPatch } from "@/lib/types";
import { useSession } from "@/components/session-provider";

/** Guiões de um dia (mais os de dias anteriores por gravar), ao vivo. */
export function useGuioes(date: string, clientId = DEFAULT_CLIENT) {
  const [all, setAll] = useState<Guiao[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const { session } = useSession();

  const reload = useCallback(async () => {
    try {
      setAll(await fetchGuioes(date, clientId));
      setError("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [date, clientId]);

  useEffect(() => {
    setLoading(true);
    reload();
    return subscribeGuioes(clientId, reload);
  }, [reload, clientId]);

  const patch = useCallback(
    async (id: string, p: GuiaoPatch) => {
      if (!session) throw new Error("Precisas do código de equipa para alterar guiões.");
      const g = await updateGuiao(id, p, session.token);
      setAll((prev) => prev.map((x) => (x.id === id ? g : x)));
      return g;
    },
    [session]
  );

  return { all, loading, error, reload, patch, canWrite: !!session };
}
