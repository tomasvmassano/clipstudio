"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { AlertTriangleIcon, CheckCircle2Icon, Loader2Icon, PlayIcon, PlusIcon, RotateCwIcon, Trash2Icon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import {
  activateConfig, cancelJob, enqueueJob, fetchConfig, fetchOverview, JOB_KIND, JOB_STATUS, retryJob, saveConfig, STAGE_LABEL,
  type AgentConfig, type Format, type Job, type Overview,
} from "@/lib/agent-config";
import { fmtDue } from "@/lib/tasks";
import { cn } from "@/lib/utils";

/*
 * Agentes: catálogo, configuração por cliente com versões, e execuções duráveis (PRD M06).
 * As execuções ficam em fila até um worker do motor as apanhar; a app não finge que correram.
 */

export default function AgentesConfigPage() {
  return <WorkspaceGate need="agents.read">{(access) => <AgentesConfig access={access} />}</WorkspaceGate>;
}

type Tab = "execucoes" | "catalogo" | "configuracao";

function AgentesConfig({ access }: { access: Access }) {
  const [o, setO] = useState<Overview | null>(null);
  const [workerAge, setWorkerAge] = useState<number | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [tab, setTab] = useState<Tab>("execucoes");
  const [msg, setMsg] = useState<{ text: string; ok: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    fetchOverview(access).then((x) => {
      if (!alive) return;
      setO(x); setErr("");
      setWorkerAge(x.worker ? (Date.now() - new Date(x.worker.last_seen).getTime()) / 60000 : null);
    }).catch((e: Error) => { if (alive) setErr(e.message); });
    const iv = setInterval(() => setRev((n) => n + 1), 15000);
    return () => { alive = false; clearInterval(iv); };
  }, [access, rev]);

  const run = useCallback(async (f: () => Promise<unknown>, ok: string) => {
    setBusy(true); setMsg(null);
    try { await f(); setMsg({ text: ok, ok: true }); setRev((n) => n + 1); }
    catch (e) { setMsg({ text: (e as Error).message, ok: false }); }
    finally { setBusy(false); }
  }, []);

  if (err) return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
    <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  if (!o) return <Skeleton className="h-64" />;

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Agentes</h1>
          <p className="text-sm text-muted-foreground">Quem faz o quê, com que modelo e regras, e o estado de cada execução. <Link className="underline" href="/agentes">Ver a sala dos agentes</Link></p>
        </div>
        <ToggleGroup value={[tab]} onValueChange={(v) => { const t = (v as string[])[0] as Tab | undefined; if (t) setTab(t); }} variant="outline" size="sm">
          <ToggleGroupItem value="execucoes">Execuções</ToggleGroupItem>
          <ToggleGroupItem value="catalogo">Catálogo</ToggleGroupItem>
          {o.can.configure && <ToggleGroupItem value="configuracao">Configuração</ToggleGroupItem>}
        </ToggleGroup>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <Card size="sm">
          <CardHeader><CardDescription>Configuração ativa</CardDescription>
            <CardTitle className="text-base">{o.active ? `Versão ${o.active.version_no}` : "Nenhuma"}</CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground">
            {o.active ? <>Ativada {o.active.activated_label ? `por ${o.active.activated_label} ` : ""}a {fmtDue(o.active.activated_at)} · {o.active.scripts_per_day} guiões por dia</> : "Sem configuração ativa os agentes não correm."}
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader><CardDescription>Corrida diária</CardDescription>
            <CardTitle className="text-base">{o.active?.schedule?.enabled ? `Todos os dias às ${o.active.schedule.time}` : "Desligada"}</CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground">
            {o.can.costs ? (o.active?.budget_eur_day ? `Limite ${o.active.budget_eur_day} EUR/dia · hoje ${Number(o.spend_today ?? 0).toFixed(2)} EUR` : `Sem limite de custo · hoje ${Number(o.spend_today ?? 0).toFixed(2)} EUR`) : "Hora no fuso do cliente."}
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader><CardDescription>Worker do motor</CardDescription>
            <CardTitle className={cn("flex items-center gap-1.5 text-base", (workerAge === null || workerAge > 10) && "text-amber-600")}>
              {workerAge === null ? <><AlertTriangleIcon className="size-4" /> Nunca ligado</> : workerAge > 10 ? <><AlertTriangleIcon className="size-4" /> Visto há {Math.round(workerAge)} min</> : <><CheckCircle2Icon className="size-4 text-emerald-600" /> Ligado</>}
            </CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground">
            {workerAge === null ? "As execuções ficam em fila até o motor ser ligado à fila (próximo passo)." : `${o.worker!.id}${o.worker!.version ? ` · ${o.worker!.version}` : ""}`}
          </CardContent>
        </Card>
      </div>

      {msg && <Alert variant={msg.ok ? "default" : "destructive"}><AlertDescription className="flex items-center justify-between gap-2">{msg.text}<Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button></AlertDescription></Alert>}

      {tab === "execucoes" && <Jobs o={o} busy={busy}
        onRun={(k) => run(() => enqueueJob(access, k), `${JOB_KIND[k]}: em fila.`)}
        onCancel={(j) => run(() => cancelJob(access, j.id), j.status === "running" ? "Pedido de cancelamento enviado ao worker." : "Execução cancelada.")}
        onRetry={(j) => run(() => retryJob(access, j.id), "Execução de volta à fila.")} />}
      {tab === "catalogo" && <Catalog o={o} />}
      {tab === "configuracao" && o.can.configure && <ConfigEditor access={access} o={o} onSaved={(t) => { setMsg({ text: t, ok: true }); setRev((n) => n + 1); }} />}
    </div>
  );
}

const STATUS_CLASS: Record<Job["status"], string> = {
  queued: "", running: "border-sky-500 text-sky-700 dark:text-sky-300", succeeded: "border-emerald-600 text-emerald-700 dark:text-emerald-300",
  failed: "border-amber-500 text-amber-700", cancelled: "text-muted-foreground", dead: "border-destructive text-destructive",
};

function Jobs({ o, busy, onRun, onCancel, onRetry }: { o: Overview; busy: boolean; onRun: (k: Job["kind"]) => void; onCancel: (j: Job) => void; onRetry: (j: Job) => void }) {
  return (
    <div className="flex flex-col gap-3">
      {o.can.run && (
        <div className="flex flex-wrap items-center gap-2">
          {(Object.keys(JOB_KIND) as Job["kind"][]).map((k) => (
            <Button key={k} size="sm" variant={k === "daily_pipeline" ? "default" : "outline"} disabled={busy || !o.active} onClick={() => onRun(k)}><PlayIcon /> {JOB_KIND[k]}</Button>
          ))}
          <span className="text-xs text-muted-foreground">Uma por tipo e por dia: carregar de novo não duplica. Os guiões gerados entram em revisão; nada é publicado sem aprovação.</span>
        </div>
      )}
      {o.jobs.length === 0 ? (
        <Alert><AlertDescription>Ainda não há execuções neste cliente.</AlertDescription></Alert>
      ) : (
        <Table>
          <TableHeader><TableRow>
            <TableHead>Execução</TableHead><TableHead>Estado</TableHead><TableHead>Tentativas</TableHead><TableHead>Progresso</TableHead>
            {o.can.costs && <TableHead>Custo</TableHead>}<TableHead />
          </TableRow></TableHeader>
          <TableBody>
            {o.jobs.map((j) => (
              <TableRow key={j.id} data-job={j.id}>
                <TableCell>
                  <div className="font-medium">{JOB_KIND[j.kind]}</div>
                  <div className="text-xs text-muted-foreground">{j.idempotency_key} · versão {j.config_version} · {j.requested_label ?? "—"}</div>
                </TableCell>
                <TableCell>
                  <Badge variant="outline" className={STATUS_CLASS[j.status]}>{JOB_STATUS[j.status]}{j.cancel_requested && j.status === "running" ? " · a cancelar" : ""}</Badge>
                  {j.status === "queued" && j.attempts > 0 && <div className="text-xs text-muted-foreground">nova tentativa {fmtDue(j.next_attempt_at)}</div>}
                  {j.last_error && <div className="max-w-xs truncate text-xs text-destructive" title={j.last_error}>{j.last_error}</div>}
                </TableCell>
                <TableCell className="tabular-nums">{j.attempts}/{j.max_attempts}</TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {j.progress ? Object.entries(j.progress).map(([k, v]) => `${k}: ${String(v)}`).join(" · ") : j.started_at ? `início ${fmtDue(j.started_at)}` : "—"}
                  {j.finished_at && <div>fim {fmtDue(j.finished_at)}</div>}
                </TableCell>
                {o.can.costs && <TableCell className="tabular-nums text-xs">{j.cost_eur != null ? `${Number(j.cost_eur).toFixed(2)} EUR` : "—"}{j.tokens_in ? <div className="text-muted-foreground">{j.tokens_in + (j.tokens_out ?? 0)} tokens</div> : null}</TableCell>}
                <TableCell className="text-right">
                  {o.can.run && (j.status === "queued" || j.status === "running") && !j.cancel_requested && <Button size="sm" variant="ghost" disabled={busy} onClick={() => onCancel(j)}><XIcon /> Cancelar</Button>}
                  {o.can.run && ["failed", "dead", "cancelled"].includes(j.status) && <Button size="sm" variant="outline" disabled={busy} onClick={() => onRetry(j)}><RotateCwIcon /> Repetir</Button>}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}

function Catalog({ o }: { o: Overview }) {
  return (
    <Table>
      <TableHeader><TableRow><TableHead>Agente</TableHead><TableHead>Etapa</TableHead><TableHead>Modelo</TableHead><TableHead>Lê</TableHead><TableHead>Escreve</TableHead></TableRow></TableHeader>
      <TableBody>
        {o.agents.map((a) => (
          <TableRow key={a.key} data-agent={a.key} className={a.enabled ? "" : "opacity-50"}>
            <TableCell><div className="font-medium">{a.name}{!a.enabled && <span className="ml-2 text-xs text-muted-foreground">(desligado)</span>}</div><div className="max-w-md text-xs text-muted-foreground">{a.description}</div></TableCell>
            <TableCell>{STAGE_LABEL[a.stage] ?? a.stage}</TableCell>
            <TableCell className="text-xs">{a.model}{a.tools.length ? <div className="text-muted-foreground">ferramentas: {a.tools.join(", ")}</div> : null}</TableCell>
            <TableCell className="text-xs text-muted-foreground">{a.reads.join(", ")}</TableCell>
            <TableCell className="text-xs text-muted-foreground">{a.writes.join(", ")}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

const lines = (s: string) => s.split("\n").map((x) => x.trim()).filter(Boolean);

function ConfigEditor({ access, o, onSaved }: { access: Access; o: Overview; onSaved: (t: string) => void }) {
  const [base, setBase] = useState<{ id: string; version_no: number; status: string } | null>(null);
  const [cfg, setCfg] = useState<AgentConfig | null>(null);
  const [models, setModels] = useState<{ key: string; label: string }[]>([]);
  const [agents, setAgents] = useState<{ key: string; name: string; default_model: string }[]>([]);
  const [notes, setNotes] = useState("");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ version_no: number; id: string; validation: { ok: boolean; errors: string[]; warnings: string[] } } | null>(null);
  const [load, setLoad] = useState<string | undefined>(undefined);

  useEffect(() => {
    let alive = true;
    fetchConfig(access, load).then((x) => {
      if (!alive) return;
      setModels(x.models ?? []); setAgents(x.agents ?? []);
      if (x.version) { setCfg(x.version.config); setBase({ id: x.version.id, version_no: x.version.version_no, status: x.version.status }); }
      else setCfg({ language: "pt-PT", voice: "", guardrails: [], formats: {}, pipeline: { scripts_per_day: 10, hooks_per_slot: 3, critic_threshold: 7.5, concurrency: 4 }, schedule: { enabled: false, time: "18:00" } });
    }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, load]);

  if (err) return <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>;
  if (!cfg) return <Skeleton className="h-64" />;
  const set = (p: Partial<AgentConfig>) => setCfg({ ...cfg, ...p });
  const setF = (k: string, p: Partial<Format>) => set({ formats: { ...cfg.formats, [k]: { ...cfg.formats[k], ...p } } });
  const sum = Object.values(cfg.formats).reduce((a, f) => a + Number(f.share || 0), 0);
  const num = (v: string) => (v === "" ? NaN : Number(v));

  const save = async (activate: boolean) => {
    setBusy(true); setResult(null);
    try {
      const v = await saveConfig(access, cfg, notes);
      setResult({ version_no: v.version_no, id: v.id, validation: v.validation });
      if (activate && v.validation.ok) { await activateConfig(v.id); onSaved(`Versão ${v.version_no} guardada e ativada.`); setLoad(v.id); }
      else if (v.validation.ok) onSaved(`Versão ${v.version_no} guardada (não ativa).`);
    } catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_18rem]">
      <div className="flex flex-col gap-4">
        <p className="text-sm text-muted-foreground">
          A editar a partir da versão {base?.version_no ?? "—"}{base?.status === "active" ? " (ativa)" : ""}. Guardar cria uma versão nova; as antigas ficam iguais e podes voltar a qualquer uma.
        </p>
        <Card><CardHeader><CardTitle className="text-base">Voz e regras</CardTitle></CardHeader>
          <CardContent className="flex flex-col gap-3 text-sm">
            <label className="flex w-40 flex-col gap-1">Idioma<Input value={cfg.language} onChange={(e) => set({ language: e.target.value })} /></label>
            <label className="flex flex-col gap-1">Voz do cliente<Textarea rows={5} value={cfg.voice} onChange={(e) => set({ voice: e.target.value })} /></label>
            <label className="flex flex-col gap-1">Léxico (separado por vírgulas)<Input value={(cfg.lexicon ?? []).join(", ")} onChange={(e) => set({ lexicon: e.target.value.split(",").map((x) => x.trim()).filter(Boolean) })} /></label>
            <label className="flex flex-col gap-1">Regras de segurança (uma por linha)<Textarea rows={5} value={cfg.guardrails.join("\n")} onChange={(e) => set({ guardrails: lines(e.target.value) })} /></label>
            <label className="flex flex-col gap-1">Áreas de notícias do Repórter (uma por linha)<Textarea rows={4} value={(cfg.news_beats ?? []).join("\n")} onChange={(e) => set({ news_beats: lines(e.target.value) })} /></label>
            <label className="flex flex-col gap-1">Lista de leitura do Filósofo (uma por linha)<Textarea rows={4} value={(cfg.reading_list ?? []).join("\n")} onChange={(e) => set({ reading_list: lines(e.target.value) })} /></label>
          </CardContent></Card>

        <Card><CardHeader><CardTitle className="text-base">Formatos <span className={cn("ml-2 text-sm font-normal", Math.abs(sum - 1) > 0.05 ? "text-destructive" : "text-muted-foreground")}>soma {sum.toFixed(2)}</span></CardTitle>
          <CardDescription>Proporção do dia, mínimo e máximo que o Aprendiz pode usar, e palavras do corpo.</CardDescription></CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            {Object.entries(cfg.formats).map(([k, f]) => (
              <div key={k} className="grid items-center gap-2 rounded-md border p-2 sm:grid-cols-[9rem_repeat(5,4.5rem)_1fr_auto]" data-format={k}>
                <b className="truncate">{k}</b>
                {(["share", "min", "max"] as const).map((x) => <Input key={x} aria-label={`${k} ${x}`} type="number" step={0.01} value={f[x]} onChange={(e) => setF(k, { [x]: num(e.target.value) })} />)}
                <Input aria-label={`${k} palavras mínimo`} type="number" value={f.palavras[0]} onChange={(e) => setF(k, { palavras: [num(e.target.value), f.palavras[1]] })} />
                <Input aria-label={`${k} palavras máximo`} type="number" value={f.palavras[1]} onChange={(e) => setF(k, { palavras: [f.palavras[0], num(e.target.value)] })} />
                <Input aria-label={`${k} descrição`} value={f.descricao ?? ""} onChange={(e) => setF(k, { descricao: e.target.value })} placeholder="Descrição" />
                <Button size="icon-sm" variant="ghost" aria-label={`Remover ${k}`} onClick={() => { const n = { ...cfg.formats }; delete n[k]; set({ formats: n }); }}><Trash2Icon /></Button>
              </div>
            ))}
            <p className="text-xs text-muted-foreground">Colunas: proporção · mínimo · máximo · palavras mín. · palavras máx. · descrição</p>
            <div><Button size="sm" variant="outline" onClick={() => {
              const name = window.prompt("Nome do formato (minúsculas, sem espaços)")?.trim().toLowerCase().replace(/\s+/g, "_");
              if (name && !cfg.formats[name]) setF(name, { share: 0, min: 0, max: 0.2, palavras: [80, 150], descricao: "" });
            }}><PlusIcon /> Formato</Button></div>
          </CardContent></Card>

        <Card><CardHeader><CardTitle className="text-base">Produção e modelos</CardTitle></CardHeader>
          <CardContent className="flex flex-col gap-3 text-sm">
            <div className="grid gap-3 sm:grid-cols-4">
              {([["scripts_per_day", "Guiões por dia"], ["hooks_per_slot", "Hooks por guião"], ["critic_threshold", "Limiar do Crítico"], ["concurrency", "Em paralelo"]] as const).map(([k, l]) => (
                <label key={k} className="flex flex-col gap-1">{l}<Input type="number" step={k === "critic_threshold" ? 0.1 : 1} value={cfg.pipeline[k]} onChange={(e) => set({ pipeline: { ...cfg.pipeline, [k]: num(e.target.value) } })} /></label>
              ))}
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              {agents.map((a) => (
                <label key={a.key} className="flex items-center justify-between gap-2">{a.name}
                  <select aria-label={`Modelo do ${a.name}`} className="h-9 rounded-md border bg-background px-2 text-sm" value={cfg.models?.[a.key] ?? a.default_model}
                    onChange={(e) => set({ models: { ...(cfg.models ?? {}), [a.key]: e.target.value } })}>
                    {models.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
                  </select>
                </label>
              ))}
            </div>
          </CardContent></Card>

        <Card><CardHeader><CardTitle className="text-base">Agenda e custo</CardTitle></CardHeader>
          <CardContent className="flex flex-wrap items-end gap-4 text-sm">
            <label className="inline-flex items-center gap-2"><input type="checkbox" checked={!!cfg.schedule?.enabled} onChange={(e) => set({ schedule: { time: cfg.schedule?.time ?? "18:00", enabled: e.target.checked } })} /> Correr todos os dias</label>
            <label className="flex flex-col gap-1">Hora (fuso do cliente)<Input type="time" value={cfg.schedule?.time ?? "18:00"} onChange={(e) => set({ schedule: { enabled: !!cfg.schedule?.enabled, time: e.target.value } })} /></label>
            {o.can.costs && <label className="flex flex-col gap-1">Limite de custo por dia (EUR)<Input type="number" step={0.5} min={0.5} value={cfg.budget_eur_day ?? ""} onChange={(e) => set({ budget_eur_day: e.target.value === "" ? null : Number(e.target.value) })} placeholder="sem limite" /></label>}
          </CardContent></Card>

        <div className="flex flex-wrap items-end gap-2">
          <label className="flex min-w-64 flex-1 flex-col gap-1 text-sm">Nota desta versão<Input value={notes} maxLength={1000} onChange={(e) => setNotes(e.target.value)} placeholder="O que mudou e porquê" /></label>
          <Button variant="outline" disabled={busy} onClick={() => save(false)}>{busy && <Loader2Icon className="animate-spin" />} Guardar versão</Button>
          <Button disabled={busy} onClick={() => save(true)}>Guardar e ativar</Button>
        </div>
        {result && (
          <Alert variant={result.validation.ok ? "default" : "destructive"}>
            <AlertDescription>
              <p className="font-medium">Versão {result.version_no}: {result.validation.ok ? "passou na validação" : "tem erros, não pode ser ativada"}</p>
              {result.validation.errors.map((e, i) => <p key={i}>• {e}</p>)}
              {result.validation.warnings.map((e, i) => <p key={i} className="text-muted-foreground">Aviso: {e}</p>)}
            </AlertDescription>
          </Alert>
        )}
      </div>

      <Card className="h-fit"><CardHeader><CardTitle className="text-base">Versões</CardTitle><CardDescription>Ativar uma antiga é voltar atrás.</CardDescription></CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {(o.versions ?? []).map((v) => (
            <div key={v.id} data-version={v.version_no} className="rounded-md border p-2">
              <div className="flex items-center justify-between gap-2">
                <b>v{v.version_no}</b>
                {v.status === "active" ? <Badge>ativa</Badge> : v.validation?.ok === false ? <Badge variant="destructive">com erros</Badge> : <Badge variant="outline">{v.status === "retired" ? "retirada" : "rascunho"}</Badge>}
              </div>
              <p className="text-xs text-muted-foreground">{v.created_label ?? "—"} · {fmtDue(v.created_at)}</p>
              {v.notes && <p className="text-xs">{v.notes}</p>}
              <div className="mt-1 flex gap-1">
                <Button size="sm" variant="ghost" onClick={() => setLoad(v.id)}>Abrir</Button>
                {v.status !== "active" && v.validation?.ok !== false && <Button size="sm" variant="outline" disabled={busy} onClick={async () => {
                  setBusy(true);
                  try { await activateConfig(v.id); onSaved(`Versão ${v.version_no} ativada.`); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
                }}>Ativar</Button>}
              </div>
            </div>
          ))}
        </CardContent></Card>
    </div>
  );
}
