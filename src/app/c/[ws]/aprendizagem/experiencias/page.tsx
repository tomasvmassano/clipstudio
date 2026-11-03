"use client";

import { useState } from "react";
import Link from "next/link";
import { ExternalLinkIcon, FlaskConicalIcon, Loader2Icon, PlusIcon, RepeatIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { LearnState, selectCls, useLoad } from "@/components/learn/learn-shared";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import {
  DIMENSION_LABEL, EXP_STATUS_LABEL, OUTCOME_LABEL, actExperiment, fetchExperiment, fetchExperiments, fetchRecommendations, fetchWinners, repeatWinner,
  saveExperiment, type ExpDimension, type ExpOutcome, type ExpResults, type Experiment, type ExperimentList, type Winner,
} from "@/lib/learn";
import { fmtIdx } from "@/lib/perf-format";
import { clientPath } from "@/lib/ws-path";

/*
 * Experiências de hooks e formatos (FR-17-11), repetir vencedor (FR-17-12) e recomendações (SCALE-06). ADR-0037.
 * Tudo lê o centro de desempenho com o mesmo índice; nada muda estratégia nem publica sozinho. Em teste: learn.experiments.
 */

export default function ExperienciasPage() {
  return (
    <WorkspaceGate need="learn.read">
      {(access) => <FlagGate flag="learn.experiments" ws={access.ws}><LearnView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

const when = (iso: string) => new Date(iso).toLocaleDateString("pt-PT", { day: "numeric", month: "short", year: "numeric" });

function LearnView({ access }: { access: Access }) {
  const [tab, setTab] = useState("experiencias");
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="min-w-0">
        <h1 className="text-2xl font-semibold tracking-tight">Experiências e vencedores</h1>
        <p className="text-sm text-muted-foreground">
          Testar hooks e formatos com regras fixadas antes de ver os dados, repetir o que ganhou como proposta para aprovar, e ver as recomendações com a evidência e os limites.
          Comparações entre publicações reais mostram associação, não provam causa.
        </p>
      </div>
      <Tabs value={tab} onValueChange={(v) => setTab(String(v))}>
        <div className="max-w-full overflow-x-auto">
          <TabsList aria-label="Secções">
            <TabsTrigger value="experiencias">Experiências</TabsTrigger>
            <TabsTrigger value="vencedores">Vencedores</TabsTrigger>
            <TabsTrigger value="recomendacoes">Recomendações</TabsTrigger>
          </TabsList>
        </div>
        <TabsContent value="experiencias" className="pt-3"><WidgetBoundary label="Experiências"><Experiments access={access} /></WidgetBoundary></TabsContent>
        <TabsContent value="vencedores" className="pt-3"><WidgetBoundary label="Vencedores"><Winners access={access} /></WidgetBoundary></TabsContent>
        <TabsContent value="recomendacoes" className="pt-3"><WidgetBoundary label="Recomendações"><Recommendations access={access} /></WidgetBoundary></TabsContent>
      </Tabs>
    </div>
  );
}

// ───────── experiências ─────────
function Experiments({ access }: { access: Access }) {
  const list = useLoad(() => fetchExperiments(access), access.ws);
  const [open, setOpen] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const l = list.data;
  return (
    <LearnState loading={list.loading} error={list.error} reload={list.reload} label="as experiências" forbidden="Não tens acesso às experiências deste cliente.">
      {l && (
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm text-muted-foreground">Mínimo por variante sugerido: {l.params.min_sample} publicações com índice. Abaixo disso não há líder.</p>
            <div className="flex gap-2">
              <Button size="sm" variant="outline" onClick={list.reload}><RotateCwIcon /> Atualizar</Button>
              {l.can_manage && <Button size="sm" onClick={() => setCreating(true)} disabled={l.accounts.length === 0}><PlusIcon /> Experiência nova</Button>}
            </div>
          </div>
          {l.can_manage && l.accounts.length === 0 && <p className="text-sm text-muted-foreground">Este cliente ainda não tem contas próprias: sem contas não há publicações para comparar.</p>}
          {l.experiments.length === 0 ? (
            <div className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">Ainda não há experiências.</div>
          ) : (
            <ul className="grid gap-3 md:grid-cols-2">
              {l.experiments.map((e) => (
                <li key={e.id}>
                  <button type="button" data-experiment={e.id} onClick={() => setOpen(e.id)}
                    className="flex w-full flex-col gap-1 rounded-lg border p-3 text-left transition-colors hover:bg-muted/60">
                    <span className="flex flex-wrap items-center gap-2">
                      <span className="font-medium">{e.title}</span>
                      <Badge variant={e.status === "a_decorrer" ? "default" : "outline"}>{EXP_STATUS_LABEL[e.status]}</Badge>
                      {e.outcome && <Badge variant="secondary">{OUTCOME_LABEL[e.outcome]}</Badge>}
                    </span>
                    <span className="line-clamp-2 text-sm text-muted-foreground">{e.hypothesis}</span>
                    <span className="text-xs text-muted-foreground">
                      {DIMENSION_LABEL[e.dimension]} · {e.variants.map((v) => `${v.key}: ${v.label}`).join(" vs ")} · {when(e.window_start)} a {when(e.window_end)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          <Sheet open={creating} onOpenChange={setCreating}>
            <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
              <SheetHeader>
                <SheetTitle>Experiência nova</SheetTitle>
                <SheetDescription>Fica em rascunho. Ao começar, a hipótese, as variantes, as contas, a janela e o critério ficam fechados.</SheetDescription>
              </SheetHeader>
              {creating && <ExperimentForm access={access} list={l} onSaved={(e) => { setCreating(false); list.reload(); setOpen(e.id); }} />}
            </SheetContent>
          </Sheet>
          <Sheet open={!!open} onOpenChange={(o) => { if (!o) setOpen(null); }}>
            <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
              {open && <ExperimentDetail key={open} access={access} id={open} canManage={l.can_manage} accounts={l.accounts} onChanged={list.reload} />}
            </SheetContent>
          </Sheet>
        </div>
      )}
    </LearnState>
  );
}

const DIMS: ExpDimension[] = ["hook_mechanism", "hook_index", "formato", "edit_style_key"];
const MECHS = ["contra", "numero", "ego", "confissao", "segredo", "pergunta"];
const isoDay = (d: Date) => d.toISOString().slice(0, 10);

function ExperimentForm({ access, list, onSaved }: { access: Access; list: ExperimentList; onSaved: (e: Experiment) => void }) {
  const today = new Date();
  const [title, setTitle] = useState("");
  const [hypothesis, setHypothesis] = useState("");
  const [dimension, setDimension] = useState<ExpDimension>("hook_mechanism");
  const [variants, setVariants] = useState([{ key: "A", value: "", label: "" }, { key: "B", value: "", label: "" }]);
  const [accounts, setAccounts] = useState<string[]>(list.accounts.map((a) => a.id));
  const [start, setStart] = useState(isoDay(today));
  const [end, setEnd] = useState(isoDay(new Date(today.getTime() + 21 * 86400000)));
  const [age, setAge] = useState<"24h" | "72h" | "7d">("72h");
  const [minN, setMinN] = useState(list.params.min_sample);
  const [ratio, setRatio] = useState("1.2");
  const [note, setNote] = useState("");
  const [external, setExternal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const setV = (i: number, p: Partial<{ value: string; label: string }>) => setVariants((vs) => vs.map((v, j) => (j === i ? { ...v, ...p } : v)));
  const submit = async () => {
    setBusy(true); setErr("");
    try {
      onSaved(await saveExperiment(access, null, {
        title, hypothesis, dimension, variants: variants.map((v) => ({ key: v.key, value: v.value.trim(), label: v.label.trim() || v.value.trim() })),
        accounts, window_start: start, window_end: end, age, min_per_variant: minN, decision_ratio: Number(ratio.replace(",", ".")),
        decision_note: note, include_external: external,
      }));
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <form className="flex flex-col gap-3 px-4 pb-8 text-sm" onSubmit={(e) => { e.preventDefault(); void submit(); }}>
      <label className="flex flex-col gap-1">Título<Input value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} required /></label>
      <label className="flex flex-col gap-1">Hipótese
        <Textarea value={hypothesis} maxLength={1000} onChange={(e) => setHypothesis(e.target.value)} placeholder="Ex.: hooks com número prendem mais do que perguntas nesta conta." required />
      </label>
      <label className="flex flex-col gap-1">O que varia
        <select className={selectCls} value={dimension} onChange={(e) => { setDimension(e.target.value as ExpDimension); setVariants((vs) => vs.map((v) => ({ ...v, value: "" }))); }}>
          {DIMS.map((d) => <option key={d} value={d}>{DIMENSION_LABEL[d]}</option>)}
        </select>
      </label>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1">Variantes</legend>
        {variants.map((v, i) => (
          <div key={v.key} className="flex flex-wrap items-center gap-2">
            <span className="w-5 font-mono">{v.key}</span>
            {dimension === "hook_mechanism" ? (
              <select aria-label={`Valor da variante ${v.key}`} className={selectCls} value={v.value} onChange={(e) => setV(i, { value: e.target.value })}>
                <option value="">Mecanismo…</option>{MECHS.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
            ) : dimension === "hook_index" ? (
              <select aria-label={`Valor da variante ${v.key}`} className={selectCls} value={v.value} onChange={(e) => setV(i, { value: e.target.value })}>
                <option value="">Hook…</option>{[0, 1, 2, 3, 4].map((h) => <option key={h} value={String(h)}>Hook {h + 1}</option>)}
              </select>
            ) : (
              <Input aria-label={`Valor da variante ${v.key}`} className="h-8 w-40" value={v.value} maxLength={100}
                placeholder={dimension === "formato" ? "ex.: lista" : "ex.: S13"} onChange={(e) => setV(i, { value: e.target.value })} />
            )}
            <Input aria-label={`Nome da variante ${v.key}`} className="h-8 min-w-[8rem] flex-1" value={v.label} maxLength={80} placeholder="Nome (opcional)" onChange={(e) => setV(i, { label: e.target.value })} />
            {variants.length > 2 && <Button type="button" size="sm" variant="ghost" onClick={() => setVariants((vs) => vs.filter((_, j) => j !== i))}>Tirar</Button>}
          </div>
        ))}
        {variants.length < 6 && (
          <Button type="button" size="sm" variant="outline" className="self-start"
            onClick={() => setVariants((vs) => [...vs, { key: "ABCDEF"[vs.length], value: "", label: "" }])}>Mais uma variante</Button>
        )}
      </fieldset>
      <fieldset className="flex flex-col gap-1">
        <legend className="mb-1">Contas</legend>
        {list.accounts.map((a) => (
          <label key={a.id} className="flex items-center gap-2">
            <input type="checkbox" checked={accounts.includes(a.id)} onChange={(e) => setAccounts((x) => (e.target.checked ? [...x, a.id] : x.filter((y) => y !== a.id)))} />
            @{a.handle} · {a.platform}
          </label>
        ))}
      </fieldset>
      <div className="grid grid-cols-2 gap-2">
        <label className="flex flex-col gap-1">Início da janela<Input type="date" value={start} onChange={(e) => setStart(e.target.value)} required /></label>
        <label className="flex flex-col gap-1">Fim da janela<Input type="date" value={end} onChange={(e) => setEnd(e.target.value)} required /></label>
        <label className="flex flex-col gap-1">Medir às
          <select className={selectCls} value={age} onChange={(e) => setAge(e.target.value as typeof age)}>
            <option value="24h">24 h</option><option value="72h">72 h</option><option value="7d">7 dias</option>
          </select>
        </label>
        <label className="flex flex-col gap-1">Mínimo por variante<Input type="number" min={3} max={500} value={minN} onChange={(e) => setMinN(Number(e.target.value))} /></label>
      </div>
      <label className="flex flex-col gap-1">Critério de decisão: a mediana do líder tem de ser pelo menos
        <span className="flex items-center gap-2"><Input className="h-8 w-20" inputMode="decimal" value={ratio} onChange={(e) => setRatio(e.target.value)} /> vezes a segunda</span>
      </label>
      <label className="flex flex-col gap-1">Nota sobre a decisão (opcional)<Input value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} /></label>
      <label className="flex items-center gap-2"><input type="checkbox" checked={external} onChange={(e) => setExternal(e.target.checked)} />Incluir publicações externas (importadas, linhagem inferida)</label>
      {err && <p className="text-destructive" role="alert">{err}</p>}
      <Button type="submit" disabled={busy || accounts.length === 0 || variants.some((v) => !v.value.trim())}>{busy && <Loader2Icon className="animate-spin" />}Guardar rascunho</Button>
    </form>
  );
}

function ExperimentDetail({ access, id, canManage, accounts, onChanged }: {
  access: Access; id: string; canManage: boolean; accounts: { id: string; handle: string; platform: string }[]; onChanged: () => void;
}) {
  const exp = useLoad(() => fetchExperiment(access, id), id);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [outcome, setOutcome] = useState<ExpOutcome>("inconclusiva");
  const [conclusion, setConclusion] = useState("");
  const [lever, setLever] = useState("");
  const e = exp.data;
  const act = async (action: "start" | "conclude" | "cancel") => {
    setBusy(true); setErr("");
    try { exp.setData(await actExperiment(access, id, action, action === "conclude" ? { outcome, conclusion, lever } : {})); onChanged(); }
    catch (x) { setErr((x as Error).message); } finally { setBusy(false); }
  };
  const res = e?.results ?? e?.preview ?? null;
  return (
    <>
      <SheetHeader>
        <SheetTitle className="flex items-center gap-2"><FlaskConicalIcon className="size-4" />{e?.title ?? "Experiência"}</SheetTitle>
        <SheetDescription>{e ? `${EXP_STATUS_LABEL[e.status]}${e.outcome ? ` · ${OUTCOME_LABEL[e.outcome]}` : ""}` : "A carregar"}</SheetDescription>
      </SheetHeader>
      <div className="flex flex-col gap-4 px-4 pb-8 text-sm">
        <LearnState loading={exp.loading} error={exp.error} reload={exp.reload} label="a experiência" forbidden="Não tens acesso a esta experiência.">
          {e && (
            <>
              <p>{e.hypothesis}</p>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                <dt className="text-muted-foreground">O que varia</dt><dd>{DIMENSION_LABEL[e.dimension]}</dd>
                <dt className="text-muted-foreground">Contas</dt><dd>{e.accounts.map((a) => { const x = accounts.find((y) => y.id === a); return x ? `@${x.handle} · ${x.platform}` : a; }).join(", ")}</dd>
                <dt className="text-muted-foreground">Janela</dt><dd>{when(e.window_start)} a {when(e.window_end)}, medido às {e.age}</dd>
                <dt className="text-muted-foreground">Critério</dt><dd>líder ≥ {String(e.decision_ratio).replace(".", ",")}× a segunda, com pelo menos {e.min_per_variant} publicações com índice por variante{e.decision_note ? `. ${e.decision_note}` : ""}</dd>
                <dt className="text-muted-foreground">Origem</dt><dd>{e.include_external ? "sistema e externas" : "só o que publicámos pela app (sistema)"}</dd>
              </dl>
              {e.status === "rascunho" && <p className="text-xs text-muted-foreground">Pré-visualização com os dados de hoje (não fica guardada).</p>}
              {e.status === "cancelada" && <p className="text-muted-foreground">Cancelada: sem resultados.</p>}
              {res && <Results r={res} e={e} />}
              {e.status === "concluida" && (
                <div className="rounded-lg border p-3">
                  <p className="font-medium">Conclusão ({e.concluded_label ?? "?"}, {e.concluded_at ? when(e.concluded_at) : ""})</p>
                  <p>{e.conclusion}</p>
                  {e.lever && <p className="text-muted-foreground">Alavanca: {e.lever}</p>}
                  <p className="mt-1 text-xs text-muted-foreground">Os números acima são a fotografia guardada no momento da conclusão.</p>
                </div>
              )}
              {err && <p className="text-destructive" role="alert">{err}</p>}
              {canManage && e.status === "rascunho" && (
                <div className="flex flex-wrap gap-2">
                  <Button disabled={busy} onClick={() => void act("start")}>{busy && <Loader2Icon className="animate-spin" />}Começar</Button>
                  <Button variant="ghost" disabled={busy} onClick={() => void act("cancel")}>Cancelar experiência</Button>
                </div>
              )}
              {canManage && e.status === "a_decorrer" && (
                <form className="flex flex-col gap-2 rounded-lg border p-3" onSubmit={(x) => { x.preventDefault(); void act("conclude"); }}>
                  <span className="font-medium">Concluir</span>
                  <label className="flex items-center gap-2">Resultado
                    <select className={selectCls} value={outcome} onChange={(x) => setOutcome(x.target.value as ExpOutcome)}>
                      <option value="inconclusiva">Inconclusiva</option>
                      <option value="confirmada" disabled={!e.results?.criterion_met}>Confirmada{e.results?.criterion_met ? "" : " (critério por cumprir)"}</option>
                      <option value="refutada">Refutada</option>
                    </select>
                  </label>
                  <Textarea aria-label="Conclusão" value={conclusion} maxLength={2000} onChange={(x) => setConclusion(x.target.value)} placeholder="O que aprendemos e com que limites" />
                  <Input aria-label="Alavanca" value={lever} maxLength={200} onChange={(x) => setLever(x.target.value)} placeholder="Alavanca a recomendar (opcional), ex.: mais hooks com número" />
                  <div className="flex flex-wrap gap-2">
                    <Button type="submit" disabled={busy || conclusion.trim().length < 10}>{busy && <Loader2Icon className="animate-spin" />}Concluir</Button>
                    <Button type="button" variant="ghost" disabled={busy} onClick={() => void act("cancel")}>Cancelar experiência</Button>
                  </div>
                </form>
              )}
            </>
          )}
        </LearnState>
      </div>
    </>
  );
}

function Results({ r, e }: { r: ExpResults; e: Experiment }) {
  return (
    <div className="flex flex-col gap-2" data-results>
      {r.warnings.map((w) => <Alert key={w}><AlertDescription>{w}</AlertDescription></Alert>)}
      <div className="overflow-x-auto">
        <Table>
          <TableHeader><TableRow>
            <TableHead>Variante</TableHead><TableHead className="text-right">Publicações</TableHead><TableHead className="text-right">Com índice</TableHead>
            <TableHead className="text-right">Mediana</TableHead><TableHead className="text-right">Melhor</TableHead><TableHead>Amostra</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {r.variants.map((v) => (
              <TableRow key={v.key} data-variant={v.key}>
                <TableCell><span className="font-mono">{v.key}</span> {v.label}{r.leader === v.key && <Badge className="ml-2">líder</Badge>}</TableCell>
                <TableCell className="text-right tabular-nums">{v.n_pubs}</TableCell>
                <TableCell className="text-right tabular-nums">{v.n}</TableCell>
                <TableCell className="text-right tabular-nums">{v.median === null ? "sem índice" : fmtIdx(v.median)}</TableCell>
                <TableCell className="text-right tabular-nums">{v.best === null ? "-" : fmtIdx(v.best)}</TableCell>
                <TableCell>{v.sufficient ? "suficiente" : <span className="text-amber-700 dark:text-amber-400">amostra insuficiente</span>}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <p>
        {r.ratio !== null
          ? <>Razão líder ÷ segunda: <b>{fmtIdx(r.ratio)}</b>. Critério ({String(e.decision_ratio).replace(".", ",")}×) {r.criterion_met ? "cumprido" : "por cumprir"}.</>
          : r.sufficient ? "Sem razão calculável (uma variante sem índice)." : "Sem líder enquanto houver variantes com amostra insuficiente."}
      </p>
      {r.by_account.length > 1 && (
        <div className="text-xs">
          <span className="font-medium">Por conta</span>
          {r.by_account.map((a) => (
            <p key={a.account_id}>@{a.handle} · {a.platform}: {Object.entries(a.per).map(([k, v]) => `${k} ${v.median === null ? "sem índice" : fmtIdx(v.median)} (${v.n})`).join(" · ")}</p>
          ))}
        </div>
      )}
      <p className="text-xs text-muted-foreground">{r.note} {r.unmatched > 0 && `${r.unmatched} publicações da janela não correspondem a nenhuma variante.`}</p>
    </div>
  );
}

// ───────── vencedores ─────────
function Winners({ access }: { access: Access }) {
  const w = useLoad(() => fetchWinners(access), access.ws);
  const [pick, setPick] = useState<Winner | null>(null);
  return (
    <LearnState loading={w.loading} error={w.error} reload={w.reload} label="os vencedores" forbidden="Não tens acesso aos vencedores deste cliente.">
      {w.data && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted-foreground">
            Publicações dos últimos {w.data.params.winner_days} dias com índice às {w.data.params.winner_age} de pelo menos {fmtIdx(w.data.params.winner_idx)}.
            Repetir cria um guião em rascunho ligado à publicação; segue a aprovação de sempre e nunca publica sozinho.
          </p>
          {w.data.items.length === 0 ? (
            <div className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">Ainda não há vencedores com índice suficiente.</div>
          ) : (
            <ul className="flex flex-col gap-2">
              {w.data.items.map((x) => (
                <li key={x.reel_id} data-winner={x.reel_id} className="flex flex-wrap items-center gap-3 rounded-lg border p-3 text-sm">
                  <span className="w-16 font-semibold tabular-nums text-emerald-600 dark:text-emerald-400">{fmtIdx(x.idx)}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{x.hook_text ?? x.title}</span>
                    <span className="text-xs text-muted-foreground">@{x.handle} · {x.platform} · {when(x.published_at)} · {x.origin === "sistema" ? "sistema" : "externo"}{x.formato ? ` · ${x.formato}` : ""}</span>
                    {x.repeats.length > 0 && (
                      <span className="mt-1 flex flex-wrap gap-1">
                        {x.repeats.map((r) => (
                          <Badge key={r.content_id} variant="outline">{r.kind === "continuacao" ? "continuação" : "variação"}: {r.content_id} ({r.status})</Badge>
                        ))}
                      </span>
                    )}
                  </span>
                  {x.url && <a className="inline-flex items-center gap-1 text-xs underline underline-offset-2" href={x.url} target="_blank" rel="noopener">Abrir <ExternalLinkIcon className="size-3" /></a>}
                  {w.data!.can_create && (x.content_id
                    ? <Button size="sm" variant="outline" onClick={() => setPick(x)}><RepeatIcon /> Repetir vencedor</Button>
                    : <span className="text-xs text-muted-foreground">sem guião ligado</span>)}
                </li>
              ))}
            </ul>
          )}
          <Sheet open={!!pick} onOpenChange={(o) => { if (!o) setPick(null); }}>
            <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
              <SheetHeader>
                <SheetTitle>Repetir vencedor</SheetTitle>
                <SheetDescription>Cria um guião em rascunho a partir do guião da publicação, com a ligação guardada. Revês, submetes e aprovas como qualquer outro.</SheetDescription>
              </SheetHeader>
              {pick && <RepeatForm key={pick.reel_id} access={access} w={pick} onDone={() => w.reload()} />}
            </SheetContent>
          </Sheet>
        </div>
      )}
    </LearnState>
  );
}

function RepeatForm({ access, w, onDone }: { access: Access; w: Winner; onDone: () => void }) {
  const [kind, setKind] = useState<"continuacao" | "variacao">("variacao");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [done, setDone] = useState<{ content_id: string; date?: string } | null>(null);
  const [ref] = useState(() => crypto.randomUUID());   // idempotência: repetir o clique não cria dois guiões
  const { ws } = useSession();
  return (
    <form className="flex flex-col gap-3 px-4 pb-8 text-sm" onSubmit={async (e) => {
      e.preventDefault(); setBusy(true); setErr("");
      try { setDone(await repeatWinner(access, w.reel_id, kind, note, ref)); onDone(); } catch (x) { setErr((x as Error).message); } finally { setBusy(false); }
    }}>
      <p><b>{fmtIdx(w.idx)}</b> · @{w.handle} · {w.hook_text ?? w.title}</p>
      <label className="flex items-center gap-2">Tipo
        <select className={selectCls} value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} disabled={!!done}>
          <option value="variacao">Variação (mesma ideia, outro ângulo)</option>
          <option value="continuacao">Continuação (parte 2)</option>
        </select>
      </label>
      <Textarea aria-label="Nota para quem escreve" value={note} maxLength={1000} onChange={(e) => setNote(e.target.value)} placeholder="O que mudar (opcional)" disabled={!!done} />
      {err && <p className="text-destructive" role="alert">{err}</p>}
      {done ? (
        <Alert><AlertDescription className="flex flex-wrap items-center gap-2">
          Proposta criada em rascunho: {done.content_id}.
          <Button size="sm" render={<Link href={clientPath(ws?.id ?? access.ws, `/guioes${done.date ? `?date=${done.date}` : ""}`)} />} nativeButton={false}>Abrir nos guiões</Button>
        </AlertDescription></Alert>
      ) : (
        <Button type="submit" disabled={busy}>{busy && <Loader2Icon className="animate-spin" />}Criar proposta</Button>
      )}
    </form>
  );
}

// ───────── recomendações ─────────
function Recommendations({ access }: { access: Access }) {
  const r = useLoad(() => fetchRecommendations(access), access.ws);
  return (
    <LearnState loading={r.loading} error={r.error} reload={r.reload} label="as recomendações" forbidden="Não tens acesso às recomendações deste cliente.">
      {r.data && (
        <div className="flex flex-col gap-3">
          <Card>
            <CardHeader><CardTitle>Limites</CardTitle><CardDescription>Ler antes de decidir.</CardDescription></CardHeader>
            <CardContent><ul className="list-disc pl-5 text-sm">{r.data.limitations.map((l) => <li key={l}>{l}</li>)}</ul></CardContent>
          </Card>
          {r.data.items.length === 0 ? (
            <div className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">
              Sem recomendações ainda: aparecem quando uma experiência é concluída como confirmada ou refutada, ou quando o centro de desempenho tem alavancas com amostra mínima.
            </div>
          ) : r.data.items.map((x, i) => (
            <Card key={i} data-recommendation={x.kind}>
              <CardHeader>
                <CardTitle className="flex flex-wrap items-center gap-2 text-base">
                  <Badge variant={x.direction === "repetir" ? "default" : "outline"}>{x.direction === "repetir" ? "Repetir" : x.direction === "evitar" ? "Evitar" : "Rever"}</Badge>
                  {x.title}
                </CardTitle>
                <CardDescription>{x.kind === "experiencia" ? "De uma experiência concluída" : "Alavanca do centro de desempenho"}</CardDescription>
              </CardHeader>
              <CardContent className="flex flex-col gap-2 text-sm">
                {x.detail && <p>{x.detail}</p>}
                <Evidence ev={x.evidence} />
                <div>
                  <span className="text-xs font-medium">Limitações</span>
                  <ul className="list-disc pl-5 text-xs text-muted-foreground">{x.limitations.filter(Boolean).map((l) => <li key={l}>{l}</li>)}</ul>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </LearnState>
  );
}

function Evidence({ ev }: { ev: Record<string, unknown> }) {
  const variants = Array.isArray(ev.variants) ? (ev.variants as { key: string; label: string; n: number; median: number | null }[]) : null;
  return (
    <div className="rounded-md bg-muted/50 px-3 py-2 text-xs">
      <span className="font-medium">Evidência: </span>
      {variants
        ? <>{variants.map((v) => `${v.key} ${v.label}: ${v.median === null ? "sem índice" : fmtIdx(v.median)} (${v.n} publicações)`).join(" · ")}
            {ev.ratio != null && ` · razão ${fmtIdx(ev.ratio as number)}`}{ev.window_start ? ` · janela ${when(String(ev.window_start))} a ${when(String(ev.window_end))}` : ""}</>
        : <>índice mediano {fmtIdx(ev.median as number)} em {String(ev.n)} publicações, às {String(ev.age)}, últimos {String(ev.days)} dias</>}
    </div>
  );
}
