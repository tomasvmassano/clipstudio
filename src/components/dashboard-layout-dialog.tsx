"use client";

import { useEffect, useState } from "react";
import { ArrowDownIcon, ArrowUpIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { ROLE_LABEL } from "@/lib/access";
import { LAYOUT_ROLES, fetchLayouts, resetLayout, saveLayout, type LayoutsResp } from "@/lib/dashboard";

const KIND_LABEL: Record<string, string> = { kpi: "Número", chart: "Gráfico", panel: "Painel" };
const selectCls = "h-9 rounded-md border bg-background px-2 text-sm";

/**
 * Escolher e ordenar os widgets do Início de cada função neste cliente (dashboard.configure).
 * Quem não tem a capacidade de um widget nunca o vê, mesmo que esteja no layout: o servidor filtra.
 */
export function LayoutDialog({ ws, myRole, onClose }: { ws: string; myRole: string; onClose: (changed: boolean) => void }) {
  const [data, setData] = useState<LayoutsResp | null>(null);
  const [role, setRole] = useState<string>(LAYOUT_ROLES.includes(myRole as (typeof LAYOUT_ROLES)[number]) ? myRole : "workspace_owner");
  const [drafts, setDrafts] = useState<Record<string, string[]>>({});
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [changed, setChanged] = useState(false);

  useEffect(() => {
    fetchLayouts(ws).then((d) => setData(d)).catch((e: Error) => setErr(e.message));
  }, [ws]);
  const current = data?.roles.find((x) => x.role === role);
  const sel = drafts[role] ?? current?.widgets ?? [];
  const setSel = (x: string[]) => setDrafts({ ...drafts, [role]: x });
  const dropDraft = () => setDrafts(Object.fromEntries(Object.entries(drafts).filter(([r]) => r !== role)));
  const dirty = !!current && JSON.stringify(current.widgets) !== JSON.stringify(sel);
  const move = (k: string, d: -1 | 1) => {
    const i = sel.indexOf(k), j = i + d;
    if (i < 0 || j < 0 || j >= sel.length) return;
    const x = [...sel]; [x[i], x[j]] = [x[j], x[i]]; setSel(x);
  };
  const run = async (f: () => Promise<LayoutsResp>) => {
    setBusy(true); setErr("");
    try { setData(await f()); dropDraft(); setChanged(true); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const byKey = new Map((data?.widgets ?? []).map((w) => [w.key, w]));
  const unused = (data?.widgets ?? []).filter((w) => !sel.includes(w.key));

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(changed); }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Personalizar o Início</DialogTitle>
          <DialogDescription>Escolhe o que cada função vê neste cliente e por que ordem. Cada pessoa só vê os números a que tem acesso.</DialogDescription>
        </DialogHeader>
        {!data ? (err ? <p className="text-sm text-destructive" role="alert">{err}</p> : <Skeleton className="h-64" />) : (
          <div className="flex flex-col gap-4 text-sm">
            <label className="flex flex-col gap-1">Função
              <select aria-label="Função" className={selectCls} value={role} disabled={busy || dirty} onChange={(e) => setRole(e.target.value)}>
                {LAYOUT_ROLES.map((r) => {
                  const x = data.roles.find((y) => y.role === r);
                  return <option key={r} value={r}>{ROLE_LABEL[r] ?? r}{x?.customized ? " (personalizado)" : ""}</option>;
                })}
              </select>
              {dirty && <span className="text-xs text-muted-foreground">Guarda ou desfaz antes de mudar de função.</span>}
            </label>
            <div>
              <p className="mb-2 font-medium">No Início ({sel.length})</p>
              {sel.length === 0 && <p className="text-xs text-muted-foreground">Escolhe pelo menos um widget.</p>}
              <ol className="flex flex-col gap-1">
                {sel.map((k, i) => {
                  const w = byKey.get(k);
                  return (
                    <li key={k} className="flex items-center gap-2 rounded-md border px-2 py-1.5">
                      <span className="w-14 shrink-0 text-xs text-muted-foreground">{KIND_LABEL[w?.kind ?? ""] ?? ""}</span>
                      <span className="flex-1">{w?.label ?? k}</span>
                      <Button size="icon-sm" variant="ghost" aria-label={`Subir ${w?.label}`} disabled={i === 0} onClick={() => move(k, -1)}><ArrowUpIcon /></Button>
                      <Button size="icon-sm" variant="ghost" aria-label={`Descer ${w?.label}`} disabled={i === sel.length - 1} onClick={() => move(k, 1)}><ArrowDownIcon /></Button>
                      <Button size="sm" variant="ghost" onClick={() => setSel(sel.filter((x) => x !== k))}>Tirar</Button>
                    </li>
                  );
                })}
              </ol>
            </div>
            {unused.length > 0 && (
              <div>
                <p className="mb-2 font-medium">Disponíveis</p>
                <ul className="flex flex-col gap-1">
                  {unused.map((w) => (
                    <li key={w.key} className="flex items-start gap-2 rounded-md border border-dashed px-2 py-1.5">
                      <span className="w-14 shrink-0 text-xs text-muted-foreground">{KIND_LABEL[w.kind]}</span>
                      <span className="flex flex-1 flex-col">
                        {w.label}
                        <span className="text-xs text-muted-foreground">{w.description}</span>
                      </span>
                      <Button size="sm" variant="outline" disabled={sel.length >= 30} onClick={() => setSel([...sel, w.key])}>Pôr</Button>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          </div>
        )}
        <DialogFooter className="flex-wrap gap-2">
          {current?.customized && (
            <Button variant="ghost" disabled={busy} onClick={() => run(() => resetLayout(ws, role))}>Repor o original desta função</Button>
          )}
          {dirty && <Button variant="ghost" disabled={busy} onClick={dropDraft}>Desfazer</Button>}
          <Button variant="outline" onClick={() => onClose(changed)}>Fechar</Button>
          <Button disabled={busy || !dirty || sel.length === 0} onClick={() => run(() => saveLayout(ws, role, sel))}>
            {busy && <Loader2Icon className="animate-spin" />} Guardar para {ROLE_LABEL[role] ?? role}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
