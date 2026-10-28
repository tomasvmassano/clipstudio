"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  clampPrefs, DEFAULT_KEYS, deviceId, fetchServerPrefs, readLocalPrefs, saveServerPrefs, writeLocalPrefs,
  type TpAction, type TpPrefs,
} from "@/lib/recording";

/**
 * Preferências do teleprompter por utilizador e dispositivo (FR-03-05).
 * Guarda sempre neste dispositivo; com conta individual também no servidor (o iPad e o computador têm as suas).
 * Com código de equipa fica só no dispositivo.
 */
export function useTpPrefs(server: boolean) {
  const [prefs, setPrefs] = useState<TpPrefs>(readLocalPrefs);
  const [syncError, setSyncError] = useState("");
  const dirty = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!server) return;
    let alive = true;
    fetchServerPrefs(deviceId())
      .then((p) => { if (alive && p && !dirty.current) { const c = clampPrefs(p); setPrefs(c); writeLocalPrefs(c); } })
      .catch((e: Error) => { if (alive) setSyncError(e.message); });
    return () => { alive = false; };
  }, [server]);

  const update = useCallback((patch: Partial<TpPrefs> | ((p: TpPrefs) => Partial<TpPrefs>)) => {
    dirty.current = true;
    setPrefs((prev) => {
      const next = clampPrefs({ ...prev, ...(typeof patch === "function" ? patch(prev) : patch) });
      writeLocalPrefs(next);
      if (server) {
        if (timer.current) clearTimeout(timer.current);
        timer.current = setTimeout(() => {
          saveServerPrefs(deviceId(), next).then(() => setSyncError("")).catch((e: Error) => setSyncError(e.message));
        }, 800);
      }
      return next;
    });
  }, [server]);

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  const keysFor = useCallback((a: TpAction) => prefs.keys[a] ?? DEFAULT_KEYS[a], [prefs.keys]);
  return { prefs, update, keysFor, syncError };
}

/** Tecla → ação, com as teclas personalizadas por cima das de origem. */
export function keyMap(keysFor: (a: TpAction) => string[]): Map<string, TpAction> {
  const m = new Map<string, TpAction>();
  (Object.keys(DEFAULT_KEYS) as TpAction[]).forEach((a) => keysFor(a).forEach((k) => { if (!m.has(k)) m.set(k, a); }));
  return m;
}
