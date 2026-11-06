"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { ClapperboardIcon, Loader2Icon, RotateCwIcon, SparklesIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadState, useLoad } from "@/components/perf/perf-shared";
import { selectCls } from "@/components/media/media-shared";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { fetchGuioes, todayDubai } from "@/lib/data";
import { EXPORT_STATUS, exportPackage, listEditDocs, listPackages, requestPackage, type PackageExportResult, type PackageJob } from "@/lib/edit-media";
import { useFlags } from "@/lib/flags";
import { fetchLibrary } from "@/lib/media";
import { packageErrorText } from "@/lib/package-errors";
import { clockText, packageWindows, windowRows } from "@/lib/package-windows";

const STYLES = [{ id: "S15", label: "S15 · frases com destaque" }, { id: "S14", label: "S14 · uma palavra de cada vez" }];
const pct = (x: number | null | undefined) => (x == null ? "?" : `${Math.round(x * 100)}%`);

const FAILED = new Set(["failed", "dead", "cancelled"]);

/** Edição automática: pedir o pacote de uma sessão, ver o progresso real do job e abrir os vídeos no editor. */
export function AutoEditView({ access }: { access: Access }) {
  const { can } = useSession();
  const mayRequest = can("edit.timeline");
  const [tick, setTick] = useState(0);
  const lib = useLoad(() => fetchLibrary(access, { kind: "video", limit: 200 }), `${access.ws}:lib:${tick}`);
  const gui = useLoad(() => fetchGuioes(access, todayDubai(), 10), `${access.ws}:g:${tick}`);
  const jobs = useLoad(() => listPackages(access), `${access.ws}:p:${tick}`);
  const docs = useLoad(() => listEditDocs(access), `${access.ws}:d:${tick}`);
  const mayExport = can("edit.export");
  // origem das janelas por guião (marcas do teleprompter ou transcrição): só com a flag edit.package_marks (ADR-0065)
  const showWindows = useFlags(access.ws, access.token)?.has("edit.package_marks") ?? false;
  const active = (jobs.last ?? []).some((j) => j.status === "queued" || j.status === "running")
    || (docs.last ?? []).some((d) => d.export?.status === "queued" || d.export?.status === "running");
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setTick((n) => n + 1), 8000);
    return () => clearInterval(id);
  }, [active]);

  // gravações: vídeos no R2 prontos, que não sejam saídas de pacotes/exports
  const recordings = useMemo(() => (lib.last?.assets ?? []).filter((a) => a.current?.storage === "r2" && a.current.state === "pronta" && !a.tags.includes("pacote")), [lib.last]);
  const [front, setFront] = useState("");
  const [side, setSide] = useState("");
  const [picked, setPicked] = useState<Set<string> | null>(null);
  const [style, setStyle] = useState("S15");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const formRef = useRef<HTMLElement>(null);
  const guioes = useMemo(() => [...(gui.last ?? [])].filter((g) => g.editorial_status !== "archived" && g.editorial_status !== "rejected")
    .sort((a, b) => (a.date === b.date ? a.n - b.n : a.date < b.date ? 1 : -1)), [gui.last]);
  const sel = picked ?? new Set(guioes.filter((g) => g.date === todayDubai()).map((g) => g.id));
  const toggle = (id: string) => { const s = new Set(sel); if (s.has(id)) s.delete(id); else s.add(id); setPicked(s); };

  const go = async () => {
    setBusy(true); setErr(null);
    try {
      const ordered = guioes.filter((g) => sel.has(g.id)).sort((a, b) => (a.date === b.date ? a.n - b.n : a.date < b.date ? -1 : 1)).map((g) => g.id);
      await requestPackage(access, front, side, ordered, style);
      setTick((n) => n + 1);
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  // "Tentar de novo" num pacote que falhou: volta a preencher o formulário com as mesmas câmaras e guiões; a pessoa confirma.
  const retryFrom = (j: PackageJob) => {
    const sideRec = recordings.find((a) => a.current!.id === j.version_id) ?? recordings.find((a) => (a.current!.original_name ?? a.title) === j.side_name);
    const frontRec = recordings.find((a) => (a.current!.original_name ?? a.title) === j.front_name && a.current!.id !== sideRec?.current!.id);
    setSide(sideRec?.current!.id ?? ""); setFront(frontRec?.current!.id ?? "");
    const ids = (j.guioes ?? []).filter((g) => !g.deleted).map((g) => g.id);
    const shown = new Set(guioes.map((g) => g.id));
    setPicked(new Set(ids.filter((id) => shown.has(id))));
    const missing = [!sideRec || !frontRec ? "uma das gravações já não está na Biblioteca (escolhe-a outra vez)" : null,
      ids.some((id) => !shown.has(id)) ? "há guiões com mais de 10 dias que não aparecem na lista" : null].filter(Boolean);
    setNotice(`Preenchi o pacote com as mesmas câmaras e guiões${missing.length ? `, mas ${missing.join(" e ")}` : ""}. Revê e carrega em Criar pacote.`);
    formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  };
  const reason = !mayRequest ? "Sem permissão para pedir pacotes (precisa de editar na linha do tempo)."
    : !front || !side ? "Escolhe as duas gravações." : front === side ? "As duas câmaras têm de ser gravações diferentes."
    : sel.size === 0 ? "Escolhe os guiões gravados nesta sessão." : null;

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Edição automática</h1>
          <p className="text-sm text-muted-foreground">Da sessão gravada às primeiras versões dos vídeos: transcrição, sincronização das câmaras, escolha dos takes por hook e legendas. Depois revês no editor e exportas.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setTick((n) => n + 1)}><RotateCwIcon /> Atualizar</Button>
      </div>

      {mayRequest && (
        <section ref={formRef} className="rounded-xl border p-4" aria-labelledby="novo-pacote">
          <h2 id="novo-pacote" className="mb-3 font-medium">Novo pacote</h2>
          {lib.error ? <LoadState loading={false} error={lib.error} reload={lib.reload} label="as gravações">{null}</LoadState> : !lib.last ? <Skeleton className="h-24" /> : recordings.length < 2 ? (
            <Alert><AlertDescription>Carrega primeiro na <Link className="underline" href={`/c/${access.ws}/biblioteca`}>Biblioteca</Link> as duas gravações da sessão (câmara da frente e câmara do lado, com o som). Precisam de estar prontas (verificadas no servidor).</AlertDescription></Alert>
          ) : (
            <div className="grid gap-3 md:grid-cols-3">
              <label className="flex flex-col gap-1 text-sm">Câmara da frente
                <select className={selectCls} value={front} onChange={(e) => setFront(e.target.value)}>
                  <option value="">Escolher…</option>
                  {recordings.map((a) => <option key={a.id} value={a.current!.id}>{a.current!.original_name ?? a.title}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">Câmara do lado (com o som da lapela)
                <select className={selectCls} value={side} onChange={(e) => setSide(e.target.value)}>
                  <option value="">Escolher…</option>
                  {recordings.map((a) => <option key={a.id} value={a.current!.id}>{a.current!.original_name ?? a.title}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">Estilo de legendas
                <select className={selectCls} value={style} onChange={(e) => setStyle(e.target.value)}>
                  {STYLES.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}
                </select>
              </label>
            </div>
          )}
          <fieldset className="mt-4">
            <legend className="mb-2 text-sm">Guiões gravados nesta sessão ({sel.size})</legend>
            {gui.error ? <LoadState loading={false} error={gui.error} reload={gui.reload} label="os guiões">{null}</LoadState> : !gui.last ? <Skeleton className="h-24" /> : guioes.length === 0 ? (
              <p className="text-sm text-muted-foreground">Sem guiões nos últimos 10 dias.</p>
            ) : (
              <div className="grid max-h-64 gap-1 overflow-y-auto rounded-md border p-2 md:grid-cols-2">
                {guioes.map((g) => (
                  <label key={g.id} className="flex items-start gap-2 rounded px-1 py-0.5 text-sm hover:bg-muted">
                    <input type="checkbox" className="mt-1" checked={sel.has(g.id)} onChange={() => toggle(g.id)} />
                    <span><span className="tabular-nums text-muted-foreground">{g.date.slice(8, 10)}/{g.date.slice(5, 7)} · {String(g.n).padStart(2, "0")}</span> {g.tema ?? "sem tema"}</span>
                  </label>
                ))}
              </div>
            )}
          </fieldset>
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <Button onClick={go} disabled={!!reason || busy}>{busy ? <Loader2Icon className="animate-spin" /> : <SparklesIcon />} Criar pacote</Button>
            {reason && <span className="text-xs text-muted-foreground">{reason}</span>}
          </div>
          {err && <p className="mt-2 text-sm text-destructive" role="alert">{err}</p>}
          {notice && <p className="mt-2 text-sm text-muted-foreground" role="status">{notice}</p>}
        </section>
      )}

      <section aria-labelledby="pacotes">
        <h2 id="pacotes" className="mb-2 font-medium">Pacotes</h2>
        <LoadState loading={!jobs.last && !jobs.error} error={jobs.error} reload={jobs.reload} label="os pacotes">
          {(jobs.last ?? []).length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há pacotes.</p> : (
            <div className="flex flex-col gap-2">{(jobs.last ?? []).map((j) => <PackageRow key={j.id} j={j} access={access} mayExport={mayExport} showWindows={showWindows} onRetry={mayRequest ? () => retryFrom(j) : undefined} onDone={() => setTick((n) => n + 1)} />)}</div>
          )}
        </LoadState>
      </section>

      <section aria-labelledby="docs">
        <h2 id="docs" className="mb-2 font-medium">Vídeos para rever</h2>
        <LoadState loading={!docs.last && !docs.error} error={docs.error} reload={docs.reload} label="os vídeos">
          {(docs.last ?? []).length === 0 ? <p className="text-sm text-muted-foreground">Sem documentos de edição.</p> : (
            <div className="overflow-x-auto rounded-md border">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-muted-foreground"><tr><th className="p-2">Vídeo</th><th className="p-2">Guião</th><th className="p-2">Versão</th><th className="p-2">Confiança da IA</th><th className="p-2">Exportação</th><th className="p-2" /></tr></thead>
                <tbody>
                  {(docs.last ?? []).slice(0, 120).map((d) => (
                    <tr key={d.asset_id} className="border-t align-top">
                      <td className="p-2">{d.title}{d.flags?.length ? <p className="mt-1 text-xs text-amber-500">{d.flags.slice(0, 2).join(" · ")}</p> : null}</td>
                      <td className="p-2">{d.guiao ? `${String(d.guiao.n).padStart(2, "0")} · ${d.guiao.tema ?? ""}` : "—"}</td>
                      <td className="p-2 tabular-nums">v{d.version_no} {d.source === "ai" ? <Badge variant="outline">IA</Badge> : null}</td>
                      <td className="p-2 tabular-nums">{d.confidence ? `hook ${pct(d.confidence.hook)} · corpo ${pct(d.confidence.body)}` : "—"}</td>
                      <td className="p-2">{d.export ? EXPORT_STATUS[d.export.status] : d.has_video ? "com vídeo" : "por exportar"}</td>
                      <td className="p-2 text-right"><Link className="underline" href={`/c/${access.ws}/editor?asset=${d.asset_id}`}>Abrir no editor</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </LoadState>
      </section>
    </div>
  );
}

function PackageRow({ j, access, mayExport, showWindows, onRetry, onDone }: { j: PackageJob; access: Access; mayExport: boolean; showWindows: boolean; onRetry?: () => void; onDone: () => void }) {
  const ws = access.ws;
  const running = j.status === "running";
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<PackageExportResult | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const exportAll = async () => {
    setBusy(true); setErr(null);
    try { setRes(await exportPackage(access, j.id)); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <div className="rounded-md border p-3 text-sm" aria-live="polite">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span><strong>{EXPORT_STATUS[j.status] === "a exportar" ? "a preparar" : EXPORT_STATUS[j.status]}</strong> · {j.front_name} + {j.side_name} · {j.guioes?.length ?? 0} guiões · {j.created_label}</span>
        <span className="text-xs text-muted-foreground">{new Date(j.created_at).toLocaleString("pt-PT", { timeZone: "Asia/Dubai" })}</span>
      </div>
      {running && <div className="mt-2 flex items-center gap-2"><Progress value={j.progress?.pct ?? 0} className="h-2 flex-1" /><span className="text-xs tabular-nums">{Math.round(j.progress?.pct ?? 0)}% · {j.progress?.step ?? ""}</span></div>}
      {j.status === "queued" && !j.worker_seen && <p className="mt-1 text-xs text-muted-foreground">O worker não está ligado agora: o pedido fica na fila e começa quando ele voltar.</p>}
      {FAILED.has(j.status) && (
        <div className="mt-2 flex flex-col gap-1" role="alert">
          <p className="text-sm text-destructive">{packageErrorText(j.last_error)}</p>
          {j.last_error && <details className="text-xs text-muted-foreground"><summary className="cursor-pointer">Detalhe técnico</summary><code className="break-all">{j.last_error}</code></details>}
          {onRetry && <div><Button size="sm" variant="outline" onClick={onRetry}><RotateCwIcon /> Tentar de novo</Button></div>}
        </div>
      )}
      {j.last_error && !FAILED.has(j.status) && j.status !== "done" && <p className="mt-1 text-xs text-muted-foreground">Tentativa anterior falhou ({packageErrorText(j.last_error)}). O worker volta a tentar sozinho.</p>}
      {j.outputs.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1">
          {j.outputs.map((o) => <Link key={o.asset_id} className="rounded border px-2 py-0.5 text-xs hover:bg-muted" href={`/c/${ws}/editor?asset=${o.asset_id}`}>{o.title}</Link>)}
        </div>
      )}
      {j.status === "done" && j.outputs.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {mayExport && (
            <Button size="sm" onClick={exportAll} disabled={busy}>
              {busy ? <Loader2Icon className="animate-spin" /> : <ClapperboardIcon />} Exportar todos ({j.outputs.length})
            </Button>
          )}
          <Link className="text-xs underline" href={`/c/${ws}/revisao?ver=videos`}>Rever os exportados</Link>
          {!mayExport && <span className="text-xs text-muted-foreground">Exportar precisa da permissão de exportar vídeos.</span>}
        </div>
      )}
      {res && (
        <p className="mt-1 text-xs text-muted-foreground" role="status">
          {res.queued} {res.queued === 1 ? "vídeo na fila" : "vídeos na fila"} para exportar. Cada um entra na revisão quando acabar, com as notas do QC.
          {res.failed.length > 0 && <span className="block text-destructive">Não deu para {res.failed.length}: {res.failed.slice(0, 3).map((f) => `${f.title} (${f.error})`).join("; ")}.</span>}
        </p>
      )}
      {err && <p className="mt-1 text-xs text-destructive" role="alert">{err} <button type="button" className="underline" onClick={exportAll}>Tentar de novo</button></p>}
      {j.status === "done" && (j.result?.missing?.length ?? 0) > 0 && <p className="mt-1 text-xs text-amber-500">Não encontrei na gravação: {j.result!.missing!.join(", ")}.</p>}
      {j.status === "done" && j.result?.offset && <p className="mt-1 text-xs text-muted-foreground">Câmaras sincronizadas pelo som (desvio {j.result.offset.front.toFixed(2)} s, confiança {j.result.offset.confidence}).</p>}
      {showWindows && j.status === "done" && <WindowsDetail j={j} />}
    </div>
  );
}

/** De onde veio a janela de cada guião na gravação longa: marcas do teleprompter (afinadas pela transcrição) ou só a transcrição. */
function WindowsDetail({ j }: { j: PackageJob }) {
  const w = packageWindows(j.result);
  if (!w) return <p className="mt-1 text-xs text-muted-foreground">Este pacote foi feito antes de o worker registar a origem das janelas por guião.</p>;
  const rows = windowRows(w, j.guioes);
  const marks = rows.filter((r) => r.source === "marcas do teleprompter").length;
  return (
    <details className="mt-2 rounded-md border p-2 text-xs">
      <summary className="cursor-pointer select-none rounded focus-visible:outline-2 focus-visible:outline-ring">
        Janelas por guião: {marks} de {rows.length} pelas marcas do teleprompter
      </summary>
      <p className={`mt-2 ${w.clock.ok ? "text-muted-foreground" : "text-amber-500"}`}>{clockText(w.clock)}</p>
      {rows.length === 0 ? <p className="mt-1 text-muted-foreground">O worker não reportou guiões.</p> : (
        <ul className="mt-2 flex flex-col gap-1">
          {rows.map((r) => (
            <li key={r.id} className="flex flex-wrap gap-x-2">
              <span className="tabular-nums text-muted-foreground">{String(r.n).padStart(2, "0")}</span>
              <span className="min-w-0 break-words">{r.tema ?? "sem tema"}</span>
              <Badge variant={r.source === "transcrição" ? "secondary" : "outline"}>{r.source}</Badge>
              {r.detail && <span className={r.warn ? "text-amber-500" : "text-muted-foreground"}>{r.detail}</span>}
              <span className={`tabular-nums ${r.warn && !r.detail ? "text-amber-500" : "text-muted-foreground"}`}>{r.windows}</span>
            </li>
          ))}
        </ul>
      )}
    </details>
  );
}
