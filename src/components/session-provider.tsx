"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { checkToken, loadSession, saveSession } from "@/lib/data";
import { LEGACY_CAPS, loadContext, type Access, type AppContext, type WorkspaceCtx } from "@/lib/access";
import type { Session } from "@/lib/types";
import { clientPath, stripWs, wsIdFromPath } from "@/lib/ws-path";

/**
 * Sessão da app (ADR-0001):
 * - "user": login Supabase; o RLS e authorize() decidem tudo no servidor.
 * - "code": código de equipa legado, só durante a transição; tudo passa por RPCs que validam o token.
 * A UI só esconde o que o servidor recusaria (AGENTS §5): nunca é a barreira.
 */
type Mode = "loading" | "anon" | "user" | "code";

type Ctx = {
  mode: Mode;
  email: string | null;
  label: string | null;
  workspaces: WorkspaceCtx[];
  /** Cliente aberto (vem do endereço /c/<cliente>); null no espaço da agência ou sem acesso. */
  ws: WorkspaceCtx | null;
  /** Cliente pedido no endereço, mesmo que a pessoa não tenha acesso (para dizer "sem acesso"). */
  wsRequested: string | null;
  /** Nome da agência de quem é staff (null para a equipa de um cliente e para o código). */
  agencyName: string | null;
  /** Último cliente aberto neste browser que ainda está na lista (para os redirecionamentos). */
  lastWs: () => string | null;
  /** Motivo, se aceitar os convites deste login falhou. */
  inviteError: string | null;
  access: Access | null;
  can: (cap: string) => boolean;
  /** Capacidades de âmbito agência (criar clientes, etc.). O servidor volta a verificar. */
  canOrg: (cap: string) => boolean;
  /** Abre outro cliente, na mesma página se estiver dentro de um cliente. */
  setWorkspace: (id: string) => void;
  signInCode: (token: string) => Promise<boolean>;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
  error: string;
  dialogOpen: boolean;
  setDialogOpen: (v: boolean) => void;
};

const SessionCtx = createContext<Ctx>({
  mode: "loading", email: null, label: null, workspaces: [], ws: null, wsRequested: null, agencyName: null, lastWs: () => null, inviteError: null,
  access: null, can: () => false, canOrg: () => false,
  setWorkspace: () => {}, signInCode: async () => false, signOut: async () => {}, refresh: async () => {}, error: "",
  dialogOpen: false, setDialogOpen: () => {},
});

const WS_KEY = "studio.ws";
const store = {
  get(k: string) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k: string, v: string | null) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch {} },
};
/** Marca para o proxy (verificação otimista): não contém o token. */
function setCodeCookie(on: boolean) {
  document.cookie = on ? "studio_code=1; path=/; max-age=2592000; samesite=lax" : "studio_code=; path=/; max-age=0; samesite=lax";
}

function legacyWorkspace(s: Session): WorkspaceCtx {
  return { id: s.client_id, name: s.client_id, handle: null, timezone: "Asia/Dubai", currency: "EUR", role: "creator", affiliation: "client_staff", capabilities: LEGACY_CAPS };
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<Mode>("loading");
  const [ctx, setCtx] = useState<AppContext | null>(null);
  const [legacy, setLegacy] = useState<Session | null>(null);
  const [error, setError] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const wsId = wsIdFromPath(pathname);

  const k = params.get("k");
  const resolve = useCallback(async () => {
    try {
      const { data } = await supabase().auth.getSession();
      setError("");
      if (data.session) {
        const c = await loadContext();
        setCtx(c);
        setLegacy(null);
        saveSession(null); // quem entra com conta deixa de ter o código guardado neste browser
        setCodeCookie(false);
        setMode("user");
        return;
      }
      const s = k ? await checkToken(k) : loadSession();
      if (k) history.replaceState(null, "", location.pathname);  // o código nunca fica no endereço
      if (s && (k || (await checkToken(s.token)))) {
        saveSession(s);
        setCodeCookie(true);
        setLegacy(s);
        setCtx(null);
        setMode("code");
        return;
      }
      saveSession(null);
      setCodeCookie(false);
      setLegacy(null);
      setCtx(null);
      setMode("anon");
    } catch (e) {
      // falha de rede ou pedido interrompido: não termina a sessão por código guardada (o servidor valida o código em cada pedido)
      setError((e as Error).message);
      const saved = k ? null : loadSession();
      if (saved) { setLegacy(saved); setCtx(null); setMode("code"); return; }
      setMode((m) => (m === "loading" ? "anon" : m));
    }
  }, [k]);

  useEffect(() => {
    // INITIAL_SESSION dispara ao subscrever, por isso também cobre o primeiro carregamento.
    const { data } = supabase().auth.onAuthStateChange((evt) => {
      if (evt === "INITIAL_SESSION" || evt === "SIGNED_IN" || evt === "SIGNED_OUT" || evt === "USER_UPDATED") void resolve();
    });
    return () => data.subscription.unsubscribe();
  }, [resolve]);

  const workspaces = useMemo(() => (mode === "code" && legacy ? [legacyWorkspace(legacy)] : ctx?.workspaces ?? []), [mode, legacy, ctx]);
  const ws = workspaces.find((w) => w.id === wsId) ?? null;
  // lembra o último cliente aberto (só para escolher para onde redirecionar as rotas antigas)
  useEffect(() => { if (ws) store.set(WS_KEY, ws.id); }, [ws]);
  const lastWs = useCallback(() => {
    const saved = store.get(WS_KEY);
    return workspaces.find((w) => w.id === saved)?.id ?? workspaces[0]?.id ?? null;
  }, [workspaces]);
  const access = useMemo<Access | null>(() => (ws ? { ws: ws.id, token: mode === "code" ? legacy?.token ?? null : null } : null), [ws, mode, legacy]);

  const value: Ctx = {
    mode,
    email: ctx?.user.email ?? null,
    label: mode === "code" ? legacy?.label ?? "Código de equipa" : ctx?.user.email ?? null,
    workspaces,
    ws,
    wsRequested: wsId,
    agencyName: mode === "user" ? ctx?.agency?.find((a) => a.status === "active")?.name ?? null : null,
    lastWs,
    inviteError: ctx?.invite_error ?? null,
    access,
    can: (cap) => !!ws?.capabilities.includes(cap),
    canOrg: (cap) => mode === "user" && !!ctx?.agency?.some((a) => a.status === "active" && a.capabilities?.includes(cap)),
    setWorkspace: (id) => { store.set(WS_KEY, id); router.push(clientPath(id, wsId ? stripWs(pathname) : "")); },
    signInCode: async (token) => {
      const s = await checkToken(token.trim()).catch(() => null);
      if (!s) return false;
      saveSession(s);
      setCodeCookie(true);
      setLegacy(s);
      setMode("code");
      router.push(clientPath(s.client_id));
      return true;
    },
    signOut: async () => {
      await supabase().auth.signOut().catch(() => undefined);
      saveSession(null);
      setCodeCookie(false);
      store.set(WS_KEY, null);
      setCtx(null);
      setLegacy(null);
      setMode("anon");
      router.push("/login");
    },
    refresh: resolve,
    error,
    dialogOpen,
    setDialogOpen,
  };
  return <SessionCtx.Provider value={value}>{children}</SessionCtx.Provider>;
}

export const useSession = () => useContext(SessionCtx);
