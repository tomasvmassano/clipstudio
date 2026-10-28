"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import { checkToken, loadSession, saveSession } from "@/lib/data";
import type { Session } from "@/lib/types";

type Ctx = {
  session: Session | null;
  ready: boolean;
  signIn: (token: string) => Promise<boolean>;
  signOut: () => void;
  /** Diálogo do código de equipa, montado uma vez no shell. */
  dialogOpen: boolean;
  setDialogOpen: (v: boolean) => void;
};
const SessionCtx = createContext<Ctx>({ session: null, ready: false, signIn: async () => false, signOut: () => {}, dialogOpen: false, setDialogOpen: () => {} });

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const params = useSearchParams();

  useEffect(() => {
    const k = params.get("k");
    (async () => {
      if (k) {
        const s = await checkToken(k);
        if (s) {
          saveSession(s);
          setSession(s);
          history.replaceState(null, "", location.pathname);
          setReady(true);
          return;
        }
      }
      setSession(loadSession());
      setReady(true);
    })();
  }, [params]);

  const signIn = async (token: string) => {
    const s = await checkToken(token.trim());
    if (!s) return false;
    saveSession(s);
    setSession(s);
    return true;
  };
  const signOut = () => {
    saveSession(null);
    setSession(null);
  };
  return <SessionCtx.Provider value={{ session, ready, signIn, signOut, dialogOpen, setDialogOpen }}>{children}</SessionCtx.Provider>;
}

export const useSession = () => useContext(SessionCtx);
