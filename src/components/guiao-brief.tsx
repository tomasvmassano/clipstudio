"use client";

import { useEffect, useMemo, useState } from "react";
import { ExternalLinkIcon, Link2Icon, Loader2Icon, Unlink2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import type { ScriptActions } from "@/components/use-guioes";
import { SOURCE_STATUS_LABEL, type BriefFields, type ContentContext, type Guiao, type Source } from "@/lib/types";

const PLATAFORMAS = ["instagram", "tiktok", "youtube", "facebook", "linkedin"];
type Form = { objetivo: string; audiencia: string; tese: string; formato: string; duracao_s: string; plataformas: string[]; cta: string; referencias: string; restricoes: string; dono: string; deadline: string };
const toForm = (c: ContentContext | null): Form => {
  const b = c?.brief;
  return {
    objetivo: b?.objetivo ?? "", audiencia: b?.audiencia ?? "", tese: b?.tese ?? "", formato: b?.formato ?? "", duracao_s: b?.duracao_s ? String(b.duracao_s) : "",
    plataformas: b?.plataformas ?? [], cta: b?.cta ?? "", referencias: b?.referencias ?? "", restricoes: b?.restricoes ?? "", dono: b?.dono ?? "", deadline: b?.deadline ?? "",
  };
};

/** Brief estruturado (FR-17-03) e fontes ligadas (FR-04-06) de um guião. Cada gravação do brief é uma versão nova. */
export function BriefSheet({ g, open, onOpenChange, actions, canEdit }: {
  g: Guiao; open: boolean; onOpenChange: (v: boolean) => void; actions: ScriptActions; canEdit: boolean;
}) {
  const [ctx, setCtx] = useState<ContentContext | null>(null);
  const [form, setForm] = useState<Form>(toForm(null));
  const [err, setErr] = useState("");
  const [saved, setSaved] = useState("");
  const [busy, setBusy] = useState(false);
  const [pool, setPool] = useState<Source[] | null>(null);
  const [pick, setPick] = useState("");
  const [rev, setRev] = useState(0);

  useEffect(() => {
    if (!open) return;
    let alive = true;
    actions.context(g.id).then((c) => { if (alive) { setCtx(c); setForm(toForm(c)); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    if (canEdit) actions.sources().then((s) => { if (alive) setPool(s); }).catch(() => { if (alive) setPool([]); });
    return () => { alive = false; };
  }, [open, g.id, actions, canEdit, rev]);

  const linkable = useMemo(() => {
    const linked = new Set((ctx?.sources ?? []).map((s) => s.id));
    return (pool ?? []).filter((s) => !linked.has(s.id) && s.status !== "descartada" && s.status !== "rejeitada");
  }, [pool, ctx]);

  const briefChangedSinceApproval = !!ctx?.approved_brief_id && !!ctx.brief && ctx.approved_brief_id !== ctx.brief.id;
  const set = (k: keyof Form) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setForm({ ...form, [k]: e.target.value });

  const save = async () => {
    setBusy(true); setErr(""); setSaved("");
    const fields: BriefFields = {
      objetivo: form.objetivo, audiencia: form.audiencia, tese: form.tese, formato: form.formato,
      duracao_s: form.duracao_s ? Number(form.duracao_s) : null, plataformas: form.plataformas, cta: form.cta,
      referencias: form.referencias, restricoes: form.restricoes, dono: form.dono, deadline: form.deadline || null,
    };
    try { const c = await actions.saveBrief(g.id, fields); setCtx(c); setForm(toForm(c)); setSaved(`Brief guardado como versão ${c.brief?.version_no}.`); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  const link = async (id: number, on: boolean) => {
    setBusy(true); setErr("");
    try { setCtx(await actions.link(g.id, id, on)); setPick(""); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>Brief e fontes do guião {g.n}</SheetTitle>
          <SheetDescription>O brief diz para que serve este conteúdo. Cada aprovação guarda o brief que estava em vigor.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-4 pb-6">
          {err && <p className="text-sm text-destructive" role="alert">{err} <Button size="sm" variant="link" onClick={() => setRev((n) => n + 1)}>Recarregar</Button></p>}
          {!ctx && !err ? <Skeleton className="h-64 w-full" /> : ctx && (
            <>
              <section className="flex flex-col gap-3" aria-label="Brief">
                <div className="flex flex-wrap items-center gap-2">
                  <h3 className="text-sm font-medium">Brief</h3>
                  {ctx.brief ? <Badge variant="outline">v{ctx.brief.version_no} de {ctx.brief_versions}</Badge> : <Badge variant="outline">ainda sem brief</Badge>}
                  {briefChangedSinceApproval && <Badge className="bg-amber-500 text-black">mudou depois da aprovação</Badge>}
                </div>
                <fieldset disabled={!canEdit || busy} className="grid gap-3">
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Objetivo<Input className="text-foreground" value={form.objetivo} onChange={set("objetivo")} placeholder="O que queremos que aconteça" /></label>
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Audiência<Input className="text-foreground" value={form.audiencia} onChange={set("audiencia")} /></label>
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Tese<Textarea rows={2} className="text-foreground" value={form.tese} onChange={set("tese")} placeholder="A ideia que o vídeo defende" /></label>
                  <div className="grid grid-cols-2 gap-3">
                    <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Formato<Input className="text-foreground" value={form.formato} onChange={set("formato")} /></label>
                    <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Duração (s)<Input className="text-foreground" type="number" min={1} max={3600} value={form.duracao_s} onChange={set("duracao_s")} /></label>
                  </div>
                  <div className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">
                    Plataformas
                    <div className="flex flex-wrap gap-1.5">
                      {PLATAFORMAS.map((p) => {
                        const on = form.plataformas.includes(p);
                        return (
                          <Button key={p} type="button" size="sm" variant={on ? "default" : "outline"} aria-pressed={on}
                            onClick={() => setForm({ ...form, plataformas: on ? form.plataformas.filter((x) => x !== p) : [...form.plataformas, p] })}>
                            {p}
                          </Button>
                        );
                      })}
                    </div>
                  </div>
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">CTA pretendido<Input className="text-foreground" value={form.cta} onChange={set("cta")} /></label>
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Referências<Textarea rows={2} className="text-foreground" value={form.referencias} onChange={set("referencias")} /></label>
                  <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Restrições<Textarea rows={2} className="text-foreground" value={form.restricoes} onChange={set("restricoes")} placeholder="O que não pode dizer, marcas, factos a confirmar" /></label>
                  <div className="grid grid-cols-2 gap-3">
                    <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Dono<Input className="text-foreground" value={form.dono} onChange={set("dono")} /></label>
                    <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Prazo<Input className="text-foreground" type="date" value={form.deadline} onChange={set("deadline")} /></label>
                  </div>
                </fieldset>
                {canEdit && (
                  <div className="flex items-center gap-3">
                    <Button size="sm" onClick={save} disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Guardar brief</Button>
                    <span className="text-xs text-muted-foreground" role="status" aria-live="polite">{saved}</span>
                  </div>
                )}
              </section>

              <section className="flex flex-col gap-2" aria-label="Fontes ligadas">
                <h3 className="text-sm font-medium">Fontes ligadas ({ctx.sources.length})</h3>
                {ctx.sources.length === 0 && <p className="text-xs text-muted-foreground">Nenhuma fonte ligada. Ligar a fonte mantém a origem dos factos e de onde veio a ideia.</p>}
                {ctx.sources.map((s) => (
                  <div key={s.id} className="flex items-start gap-2 rounded-md border p-2 text-sm">
                    <div className="min-w-0 flex-1">
                      <div className="font-medium">{s.titulo}</div>
                      <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
                        {s.kind === "talent_request" ? "pedido do talento" : s.fonte_tipo} · {SOURCE_STATUS_LABEL[s.status]}
                        {s.fonte_url && <a href={s.fonte_url} target="_blank" rel="noopener" className="inline-flex items-center gap-0.5 underline">abrir <ExternalLinkIcon className="size-3" /></a>}
                      </div>
                    </div>
                    {canEdit && <Button size="sm" variant="ghost" aria-label={`Desligar ${s.titulo}`} disabled={busy} onClick={() => link(s.id, false)}><Unlink2Icon /></Button>}
                  </div>
                ))}
                {canEdit && (
                  <div className="flex gap-2">
                    <select aria-label="Escolher fonte para ligar" className="h-9 min-w-0 flex-1 rounded-md border bg-background px-2 text-sm" value={pick} onChange={(e) => setPick(e.target.value)}>
                      <option value="">{pool === null ? "A carregar fontes…" : linkable.length ? "Escolhe uma fonte…" : "Não há fontes por ligar"}</option>
                      {linkable.map((s) => <option key={s.id} value={s.id}>{s.kind === "talent_request" ? "[pedido] " : ""}{s.titulo}</option>)}
                    </select>
                    <Button size="sm" variant="outline" disabled={!pick || busy} onClick={() => link(Number(pick), true)}><Link2Icon /> Ligar</Button>
                  </div>
                )}
              </section>
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
