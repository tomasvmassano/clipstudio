"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangleIcon, ClipboardPasteIcon, ExternalLinkIcon, Loader2Icon, RotateCwIcon, ScissorsIcon, SparklesIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { WsLink } from "@/components/ws-link";
import type { Access } from "@/lib/access";
import { adaptReference, analyzeReference, fetchReferenceDetail, type RefDetail, type RefJob } from "@/lib/references";
import { EDITORIAL_LABEL, type EditorialStatus } from "@/lib/types";

/*
 * REF-02 dissecção visível e REF-03/04 3 guiões em via rápida (PRD §45, ADR-0059). Tudo o que aparece vem da base:
 * a dissecção é uma versão imutável com modelo, agente e versão dos prompts (AGENTS §7); o estado da execução é o de
 * agent_jobs. Nada é apresentado como facto verificado.
 */

const nf = new Intl.NumberFormat("pt-PT", { notation: "compact", maximumFractionDigits: 1 });
const POLL_MS = 5000;
const POLL_MAX_MS = 15 * 60 * 1000;
const active = (j: RefJob | null | undefined) => !!j && (j.status === "queued" || j.status === "running");
const hhmm = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleTimeString("pt-PT", { hour: "2-digit", minute: "2-digit" }) : "");
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("pt-PT", { day: "2-digit", month: "short", year: "numeric" }) : "");
const mmss = (s: number | undefined) => (s == null ? "" : `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`);

function JobState({ job, workerReady, what }: { job: RefJob; workerReady: boolean; what: string }) {
  if (job.status === "queued") {
    return (
      <Alert>
        <AlertDescription className="flex flex-col gap-1">
          <span className="flex items-center gap-2"><Loader2Icon className="size-4 animate-spin" aria-hidden /> {what} em fila desde as {hhmm(job.created_at)}{job.attempts > 0 ? ` (nova tentativa ${job.attempts + 1} de ${job.max_attempts} às ${hhmm(job.next_attempt_at)})` : ""}.</span>
          {!workerReady && <span className="text-xs text-muted-foreground">O motor ainda não está a aceitar este tipo de pedido (worker por atualizar ou desligado). O pedido fica guardado e corre quando o motor estiver ligado.</span>}
        </AlertDescription>
      </Alert>
    );
  }
  if (job.status === "running") {
    const etapa = typeof job.progress?.etapa === "string" ? job.progress.etapa : null;
    const label = etapa === "recolha" ? "a recolher a transcrição e as métricas" : etapa === "disseccao" ? "a dissecar" : etapa === "guioes" ? `a escrever (${Number(job.progress?.guardados ?? 0)} de 3 gravados)` : "a correr";
    return <Alert><AlertDescription className="flex items-center gap-2"><Loader2Icon className="size-4 animate-spin" aria-hidden /> {what}: {label} (tentativa {job.attempts} de {job.max_attempts}, desde as {hhmm(job.started_at)}).</AlertDescription></Alert>;
  }
  if (job.status === "failed" || job.status === "dead") {
    return <Alert variant="destructive"><AlertDescription><b>{what} falhou</b> às {hhmm(job.finished_at ?? job.started_at)}: {job.last_error ?? "sem detalhe"}</AlertDescription></Alert>;
  }
  if (job.status === "cancelled") return <Alert><AlertDescription>{what} cancelada às {hhmm(job.finished_at)}.</AlertDescription></Alert>;
  return null;
}

export function ReferenceDissection({ access, refId, onClose, onChanged }: { access: Access; refId: number; onClose: () => void; onChanged: () => void }) {
  const [d, setD] = useState<RefDetail | null>(null);
  const [err, setErr] = useState("");
  const [actionErr, setActionErr] = useState("");
  const [version, setVersion] = useState<number | undefined>(undefined);
  const [busy, setBusy] = useState<"analyze" | "adapt" | null>(null);
  const [manual, setManual] = useState(false);
  const [transcript, setTranscript] = useState("");
  const [tick, setTick] = useState(0);
  const [stale, setStale] = useState(false);
  const pollStart = useRef<number | null>(null);

  useEffect(() => {
    let alive = true;
    fetchReferenceDetail(access, refId, version)
      .then((x) => { if (alive) { setD(x); setErr(""); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, refId, version, tick]);

  const running = active(d?.analysis_job) || active(d?.scripts_job);
  // acompanha a execução enquanto está em fila ou a correr; pára ao fim de 15 min e diz isso (sem spinner infinito)
  useEffect(() => {
    if (!running) { pollStart.current = null; return; }
    pollStart.current ??= Date.now();
    if (Date.now() - pollStart.current > POLL_MAX_MS) { setStale(true); return; }
    const t = setTimeout(() => setTick((n) => n + 1), POLL_MS);
    return () => clearTimeout(t);
  }, [running, tick]);
  const prevRunning = useRef(running);
  useEffect(() => { if (prevRunning.current && !running) onChanged(); prevRunning.current = running; }, [running, onChanged]);

  const refresh = useCallback(() => { setStale(false); pollStart.current = null; setTick((n) => n + 1); }, []);
  const analyze = async (withTranscript: boolean) => {
    setBusy("analyze"); setActionErr("");
    try { await analyzeReference(access, refId, withTranscript ? transcript : undefined); setManual(false); setTranscript(""); setVersion(undefined); refresh(); onChanged(); }
    catch (e) { setActionErr((e as Error).message); }
    finally { setBusy(null); }
  };
  const adapt = async () => {
    setBusy("adapt"); setActionErr("");
    try { await adaptReference(access, refId); refresh(); onChanged(); }
    catch (e) { setActionErr((e as Error).message); }
    finally { setBusy(null); }
  };

  const a = d?.analysis; const dis = a?.dissection; const m = a?.metrics;
  const r = d?.reference;
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="max-h-[92svh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Dissecção{r ? `: ${r.titulo}` : ""}</DialogTitle>
          <DialogDescription>Feita pelo motor a partir da transcrição e das métricas públicas. É uma leitura de IA, não um facto verificado.</DialogDescription>
        </DialogHeader>
        {err && <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{err}</span><Button size="sm" variant="outline" onClick={refresh}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>}
        {!d ? (!err && <div className="flex flex-col gap-3"><Skeleton className="h-16" /><Skeleton className="h-40" /></div>) : (
          <div className="flex flex-col gap-4 text-sm">
            {r?.url && <a href={r.url} target="_blank" rel="noopener" className="inline-flex w-fit items-center gap-1 text-xs text-muted-foreground underline-offset-2 hover:underline"><ExternalLinkIcon className="size-3" aria-hidden /> {r.url}</a>}
            {d.analysis_job && (active(d.analysis_job) || !a || d.analysis_job.created_at > a.created_at) && <JobState job={d.analysis_job} workerReady={d.worker_ready} what="Dissecção" />}
            {stale && <Alert><AlertDescription className="flex items-center justify-between gap-2"><span>Parei de atualizar sozinho ao fim de 15 minutos. A execução continua no motor.</span><Button size="sm" variant="outline" onClick={refresh}><RotateCwIcon /> Atualizar</Button></AlertDescription></Alert>}
            {actionErr && <p className="text-sm text-destructive" role="alert">{actionErr}</p>}

            {d.can.analyze && !active(d.analysis_job) && (
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant={a ? "outline" : "default"} disabled={!!busy} onClick={() => analyze(false)}>
                  {busy === "analyze" ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />} {a ? "Dissecar outra vez" : "Dissecar"}
                </Button>
                <Button size="sm" variant="ghost" aria-expanded={manual} onClick={() => setManual(!manual)}><ClipboardPasteIcon /> Colar a transcrição à mão</Button>
              </div>
            )}
            {manual && (
              <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); analyze(true); }}>
                <label className="flex flex-col gap-1 text-sm">Transcrição (o que se diz no vídeo)
                  <Textarea rows={5} value={transcript} onChange={(e) => setTranscript(e.target.value)} maxLength={20000} placeholder="Cola aqui o texto falado do vídeo" />
                </label>
                <p className="text-xs text-muted-foreground">Usa isto quando a recolha automática não está disponível ou não trouxe a transcrição. Fica registado que veio de uma pessoa.</p>
                <div><Button type="submit" size="sm" disabled={!!busy || transcript.trim().length < 20}>{busy === "analyze" && <Loader2Icon className="animate-spin" />} Dissecar com esta transcrição</Button></div>
              </form>
            )}
            {!a && !d.analysis_job && <Alert><AlertDescription>Esta referência ainda não foi dissecada.{!d.can.analyze ? " Pede a quem gere as referências deste cliente." : ""}</AlertDescription></Alert>}

            {a && dis && (
              <>
                <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                  {d.versions.length > 1 ? (
                    <select aria-label="Versão da dissecção" className="h-7 rounded-md border bg-background px-2 text-xs" value={a.version} onChange={(e) => setVersion(Number(e.target.value))}>
                      {d.versions.map((v) => <option key={v.version} value={v.version}>v{v.version} · {day(v.created_at)}</option>)}
                    </select>
                  ) : <Badge variant="outline">v{a.version}</Badge>}
                  <span>Gerado por IA a {day(a.created_at)} · modelo {a.model} · {a.agent_version} · prompts {a.prompt_version} · transcrição {a.transcript_source === "manual" ? "colada à mão" : "da recolha"}</span>
                </div>
                {(dis.afirmacoes_terceiros?.length ?? 0) > 0 && (
                  <Alert variant="destructive">
                    <AlertDescription className="flex flex-col gap-1">
                      <span className="flex items-center gap-1 font-medium"><AlertTriangleIcon className="size-4" aria-hidden /> Afirmações sobre pessoas ou entidades identificadas</span>
                      <span className="text-xs">Não são verificadas e não passam para os guiões do cliente (R-17).</span>
                      <ul className="list-disc pl-5">{dis.afirmacoes_terceiros!.map((x, i) => <li key={i}>{x.texto}{x.pessoa ? ` (${x.pessoa}${x.tipo ? `, ${x.tipo}` : ""})` : ""}</li>)}</ul>
                    </AlertDescription>
                  </Alert>
                )}
                <dl className="grid gap-3 sm:grid-cols-2">
                  <div className="sm:col-span-2"><dt className="text-xs text-muted-foreground">Hook{dis.hook?.segundos != null ? ` (primeiros ${dis.hook.segundos} s)` : ""}</dt><dd className="font-medium">“{dis.hook?.texto}”</dd>{dis.hook?.mecanismo && <dd className="text-muted-foreground">Mecanismo: {dis.hook.mecanismo}</dd>}</div>
                  <div><dt className="text-xs text-muted-foreground">Máquina</dt><dd className="font-medium">{dis.maquina}</dd>{dis.maquina_porque && <dd className="text-muted-foreground">{dis.maquina_porque}</dd>}</div>
                  <div><dt className="text-xs text-muted-foreground">Inimigo</dt><dd>{dis.inimigo || "não identificado"}</dd></div>
                  <div className="sm:col-span-2"><dt className="text-xs text-muted-foreground">Tese</dt><dd>{dis.tese}</dd></div>
                  <div><dt className="text-xs text-muted-foreground">Duração e ritmo</dt><dd>{dis.duracao_s != null ? `${Math.round(dis.duracao_s)} s` : "duração desconhecida"}{dis.palavras_por_segundo != null ? ` · ${dis.palavras_por_segundo.toLocaleString("pt-PT")} palavras/s` : ""}</dd>{dis.ritmo && <dd className="text-muted-foreground">{dis.ritmo}</dd>}</div>
                  <div>
                    <dt className="text-xs text-muted-foreground">Métricas públicas</dt>
                    {m ? (
                      <dd>
                        {m.views != null && <span><b className="tabular-nums">{nf.format(m.views)}</b> views</span>}
                        {m.comments != null && <span className="tabular-nums"> · {nf.format(m.comments)} comentários</span>}
                        {m.index != null ? <span className="block"><b className="tabular-nums">{m.index.toLocaleString("pt-PT")}×</b> a mediana do autor ({m.author_sample} vídeos recolhidos)</span>
                          : <span className="block text-xs text-muted-foreground">Sem índice: ainda não há vídeos suficientes deste autor recolhidos.</span>}
                        <span className="block text-xs text-muted-foreground" title="Números recolhidos pelo mecanismo do Scout (R-20); não são da API oficial">recolha · {day(m.collected_at)}</span>
                      </dd>
                    ) : <dd className="text-muted-foreground">Indisponíveis nesta dissecção.</dd>}
                  </div>
                  {dis.porque_funciona && <div className="sm:col-span-2"><dt className="text-xs text-muted-foreground">Porque funciona</dt><dd>{dis.porque_funciona}</dd></div>}
                </dl>
                {(dis.estrutura?.length ?? 0) > 0 && (
                  <div>
                    <h3 className="mb-1 text-xs text-muted-foreground">Estrutura</h3>
                    <ol className="flex flex-col gap-1">
                      {dis.estrutura!.map((e, i) => (
                        <li key={i} className="flex gap-2 rounded-md border px-2 py-1">
                          <span className="w-20 shrink-0 tabular-nums text-muted-foreground">{e.inicio_s != null ? `${mmss(e.inicio_s)}${e.fim_s != null ? `–${mmss(e.fim_s)}` : ""}` : ""}</span>
                          <span><b>{e.parte}</b>{e.resumo ? `: ${e.resumo}` : ""}</span>
                        </li>
                      ))}
                    </ol>
                  </div>
                )}
                <details className="rounded-md border px-3 py-2">
                  <summary className="cursor-pointer text-xs text-muted-foreground">Transcrição ({a.transcript_source === "manual" ? "colada à mão" : "da recolha"})</summary>
                  <p className="mt-2 whitespace-pre-wrap">{a.transcript}</p>
                </details>

                <section className="flex flex-col gap-2 border-t pt-3" aria-labelledby="ref-scripts">
                  <h3 id="ref-scripts" className="font-medium">3 guiões para este cliente (via rápida)</h3>
                  <p className="text-xs text-muted-foreground">O motor escreve na voz do cliente com a configuração ativa, as frases-persona aprovadas e os guiões aprovados. Adapta a ideia, não o texto: os guiões parecidos demais com a transcrição são bloqueados. Entram em revisão, nunca aprovados.</p>
                  {d.scripts_job && <JobState job={d.scripts_job} workerReady={d.worker_ready} what="Guiões" />}
                  {d.can.adapt && !active(d.scripts_job) && (
                    <div><Button size="sm" disabled={!!busy} onClick={adapt}>{busy === "adapt" ? <Loader2Icon className="animate-spin" /> : <SparklesIcon />} {d.scripts.length ? "Gerar mais 3 guiões" : "Gerar 3 guiões"}</Button></div>
                  )}
                  {d.scripts.length > 0 && (
                    <ul className="flex flex-col gap-1">
                      {d.scripts.map((s) => (
                        <li key={s.content_id} className="flex flex-wrap items-center gap-2 rounded-md border px-2 py-1">
                          <WsLink href={`/guioes?date=${s.date}`} className="font-medium underline-offset-2 hover:underline">#{s.n} {s.tema ?? "sem tema"}</WsLink>
                          <Badge variant="outline">{EDITORIAL_LABEL[s.editorial_status as EditorialStatus] ?? s.editorial_status}</Badge>
                          {s.similarity != null && <span className="text-xs text-muted-foreground">semelhança com o original {Math.round(s.similarity * 100)}%</span>}
                          <span className="text-xs text-muted-foreground">dissecção v{s.analysis_version} · {day(s.date)}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              </>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
