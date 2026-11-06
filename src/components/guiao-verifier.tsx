"use client";

import { useCallback, useEffect, useState } from "react";
import { RotateCwIcon, ShieldAlertIcon, ShieldCheckIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { ScriptActions } from "@/components/use-guioes";
import type { Guiao } from "@/lib/types";
import {
  FLAG_LABEL, KIND_LABEL, checkForHook, summary, type Verification, type VerifierFlag, type VerifierHook,
} from "@/lib/verifier-format";

const FLAG_STYLE: Record<VerifierFlag, string> = {
  ok: "border-emerald-600/40 text-emerald-700 dark:text-emerald-400",
  atencao: "border-amber-500/50 text-amber-700 dark:text-amber-400",
  rever: "border-orange-500/60 text-orange-700 dark:text-orange-400",
  juridico: "border-violet-500/60 text-violet-700 dark:text-violet-300",
  bloqueado: "bg-destructive text-white border-transparent",
};

type State = { status: "loading" | "ready" | "off" | "error"; v: Verification | null; error?: string };
const toState = (v: Verification | null | "off"): State => (v === "off" ? { status: "off", v: null } : { status: "ready", v });

/** Resultado do verificador do motor para este guião (VAR-04). Guiões do motor acabados de gravar podem ainda não o ter. */
export function useVerification(g: Guiao, actions: ScriptActions) {
  const [s, setS] = useState<State>({ status: "loading", v: null });
  const load = useCallback(async (fresh = false) => {
    try { setS(toState(await actions.verification(g.id, fresh))); }
    catch (e) { setS({ status: "error", v: null, error: (e as Error).message }); }
  }, [actions, g.id]);
  useEffect(() => {
    let alive = true;
    let retry: ReturnType<typeof setTimeout> | undefined;
    actions.verification(g.id).then((v) => {
      if (!alive) return;
      setS(toState(v));
      // o worker grava a verificação logo a seguir ao guião: se o guião é de agora, volta a ver uma vez
      if (!v && g.origem === "motor" && Date.now() - new Date(g.created_at).getTime() < 3 * 60_000) {
        retry = setTimeout(() => { if (alive) void load(true); }, 8000);
      }
    }, (e: Error) => { if (alive) setS({ status: "error", v: null, error: e.message }); });
    return () => { alive = false; if (retry) clearTimeout(retry); };
  }, [actions, g.id, g.origem, g.created_at, load]);
  return { ...s, reload: () => load(true) };
}

/** Marcas de um hook, com o porquê de cada uma (teclado: o resumo abre e fecha). */
export function HookChecks({ v, text }: { v: Verification | null; text: string }) {
  if (!v) return null;
  const { hook, stale } = checkForHook(v.result, text);
  if (stale) return <span className="text-[11px] font-normal text-muted-foreground">verificado noutro texto: o hook mudou depois</span>;
  if (!hook) return null;
  return <HookDetail hook={hook} />;
}

function HookDetail({ hook }: { hook: VerifierHook }) {
  const claims = hook.afirmacoes;
  const lang = hook.lingua && !hook.lingua.ok ? hook.lingua.problemas : [];
  if (!claims.length && !lang.length) return null;
  return (
    <details className="group text-xs font-normal">
      <summary className="flex cursor-pointer list-none flex-wrap items-center gap-1 rounded-sm focus-visible:outline-2 focus-visible:outline-ring" aria-label="Verificador: ver porquê">
        {claims.map((c, k) => (
          <Badge key={k} variant="outline" className={cn("text-[10px]", FLAG_STYLE[c.marca])}>{KIND_LABEL[c.tipo]}: {FLAG_LABEL[c.marca]}</Badge>
        ))}
        {lang.length > 0 && <Badge variant="outline" className={cn("text-[10px]", FLAG_STYLE.rever)}>PT-PT: rever</Badge>}
        <span className="text-[11px] text-muted-foreground underline underline-offset-2">porquê</span>
      </summary>
      <ul className="mt-1 flex flex-col gap-1 border-l-2 pl-2 text-muted-foreground">
        {claims.map((c, k) => (
          <li key={k}>
            <span className="font-medium text-foreground">{KIND_LABEL[c.tipo]}</span> «{c.trecho}»: {c.motivo ?? FLAG_LABEL[c.marca]}
            {c.fonte && (
              <> {" "}<a href={c.fonte} target="_blank" rel="noopener" className="underline underline-offset-2">fonte{c.fonte_data ? ` de ${c.fonte_data}` : " sem data"}</a></>
            )}
          </li>
        ))}
        {lang.map((p, k) => <li key={`l${k}`}><span className="font-medium text-foreground">PT-PT</span>: {p}</li>)}
      </ul>
    </details>
  );
}

/** Resumo do verificador no cartão do guião. Nunca chumba nem aprova: quem revê decide. */
export function VerifierSummary({ g, state }: { g: Guiao; state: ReturnType<typeof useVerification> }) {
  const { status, v, error, reload } = state;
  if (status === "off") return null;
  if (status === "error") {
    return (
      <p role="alert" className="flex flex-wrap items-center gap-2 text-xs text-destructive">
        Não foi possível ler o verificador: {error}
        <Button size="xs" variant="outline" onClick={() => void reload()}><RotateCwIcon /> Tentar de novo</Button>
      </p>
    );
  }
  if (status === "loading") return g.origem === "motor" ? <p className="text-xs text-muted-foreground" aria-live="polite">A ler o verificador…</p> : null;
  if (!v) {
    if (g.origem !== "motor") return null;
    return (
      <p className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        Sem verificação do motor para este guião (gerado antes do verificador ou não gravada). Rever as afirmações à mão.
        <Button size="xs" variant="ghost" onClick={() => void reload()}><RotateCwIcon /> Ver de novo</Button>
      </p>
    );
  }
  const r = v.result;
  const bad = v.marca === "bloqueado" || v.marca === "juridico";
  const Icon = v.marca === "ok" ? ShieldCheckIcon : ShieldAlertIcon;
  const extra = r.lingua_texto && !r.lingua_texto.ok ? ` Legenda ou comentário: ${r.lingua_texto.problemas.join("; ")}.` : "";
  return (
    <div className={cn("flex flex-col gap-0.5 rounded-md border px-3 py-2 text-xs", bad ? "border-destructive/50" : "border-border")} data-verifier={v.marca}>
      <p className="flex flex-wrap items-center gap-1.5">
        <Icon className={cn("size-3.5", bad ? "text-destructive" : "text-muted-foreground")} aria-hidden />
        <span className="font-medium">Verificador</span>
        <Badge variant="outline" className={cn("text-[10px]", FLAG_STYLE[v.marca])}>{FLAG_LABEL[v.marca]}</Badge>
        <span className="text-muted-foreground">{summary(r)}{extra}</span>
      </p>
      <p className="text-[11px] text-muted-foreground">
        Verificador {v.verifier_version}{v.model ? ` · ${v.model}` : ""}{v.prompts_version ? ` · prompts ${v.prompts_version}` : ""}
        {r.lista_persona === false ? " · sem lista de frases-persona" : v.persona_version != null ? ` · lista de frases-persona v${v.persona_version}` : ""}
        {r.llm === "mock" ? " · modo de teste" : ""}
      </p>
    </div>
  );
}
