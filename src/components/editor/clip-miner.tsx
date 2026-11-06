"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { ClapperboardIcon, Loader2Icon, RotateCwIcon, ScissorsIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadState, useLoad } from "@/components/perf/perf-shared";
import { selectCls } from "@/components/media/media-shared";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { exportClips, listClips, requestClips, type ClipJob } from "@/lib/clips";
import { clipMasters, clipTime, polemicText, scoreText } from "@/lib/clips-format";
import { EXPORT_STATUS, type PackageExportResult } from "@/lib/edit-media";
import { fetchLibrary } from "@/lib/media";

const COUNTS = [5, 6, 7, 8, 9, 10];

/** Cortes de vídeos longos: escolher o vídeo, pedir, ver o progresso real do job, rever os cortes e exportar todos. */
export function ClipMinerView({ access }: { access: Access }) {
  const { can } = useSession();
  const mayRequest = can("clips.mine");
  const mayExport = can("edit.export");
  const [tick, setTick] = useState(0);
  const lib = useLoad(() => fetchLibrary(access, { kind: "video", limit: 200 }), `${access.ws}:lib:${tick}`);
  const jobs = useLoad(() => listClips(access), `${access.ws}:clips:${tick}`);
  const active = (jobs.last ?? []).some((j) => j.status === "queued" || j.status === "running"
    || j.clips.some((c) => c.export?.status === "queued" || c.export?.status === "running"));
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setTick((n) => n + 1), 8000);
    return () => clearInterval(id);
  }, [active]);

  const masters = useMemo(() => clipMasters(lib.last?.assets ?? []), [lib.last]);
  const [version, setVersion] = useState("");
  const [count, setCount] = useState(8);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const go = async (v = version, n = count) => {
    setBusy(true); setErr(null);
    try { await requestClips(access, v, n); setTick((x) => x + 1); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const reason = !mayRequest ? "Sem permissão para procurar cortes." : !version ? "Escolhe o vídeo longo." : null;

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Cortes de vídeos longos</h1>
          <p className="text-sm text-muted-foreground">De um podcast, entrevista ou vlog na Biblioteca a 5-10 cortes verticais propostos pela IA, com pontuação, justificação, etiquetas e riscos. A pontuação ordena os candidatos: não é uma previsão de visualizações. Revês cada corte no editor e exportas.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setTick((n) => n + 1)}><RotateCwIcon /> Atualizar</Button>
      </div>

      {mayRequest && (
        <section className="rounded-xl border p-4" aria-labelledby="novo-pedido">
          <h2 id="novo-pedido" className="mb-3 font-medium">Encontrar cortes</h2>
          {lib.error ? <LoadState loading={false} error={lib.error} reload={lib.reload} label="os vídeos">{null}</LoadState> : !lib.last ? <Skeleton className="h-16" /> : masters.length === 0 ? (
            <Alert><AlertDescription>Carrega primeiro na <Link className="underline" href={`/c/${access.ws}/biblioteca`}>Biblioteca</Link> o ficheiro original do vídeo longo (o master, em 4K quando houver). Tem de estar pronto (verificado no servidor) e ter pelo menos 2 minutos. Um link do YouTube não serve: a plataforma não permite descarregar.</AlertDescription></Alert>
          ) : (
            <div className="grid gap-3 md:grid-cols-[1fr_auto]">
              <label className="flex flex-col gap-1 text-sm">Vídeo longo
                <select className={selectCls} value={version} onChange={(e) => setVersion(e.target.value)}>
                  <option value="">Escolher…</option>
                  {masters.map((a) => <option key={a.id} value={a.current!.id}>{a.current!.original_name ?? a.title}{a.current!.media_info?.duration ? ` · ${clipTime(a.current!.media_info.duration)}` : ""}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">Cortes
                <select className={selectCls} value={count} onChange={(e) => setCount(Number(e.target.value))}>
                  {COUNTS.map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </label>
            </div>
          )}
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <Button onClick={() => go()} disabled={!!reason || busy}>{busy ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />} Encontrar cortes</Button>
            {reason && <span className="text-xs text-muted-foreground">{reason}</span>}
          </div>
          <p className="mt-2 text-xs text-muted-foreground">Enquadramento vertical: por agora é um corte ao centro do plano (sem seguir quem fala). Ajusta o zoom no editor quando o orador não estiver ao centro.</p>
          {err && <p className="mt-2 text-sm text-destructive" role="alert">{err}</p>}
        </section>
      )}

      <section aria-labelledby="pedidos">
        <h2 id="pedidos" className="mb-2 font-medium">Pedidos</h2>
        <LoadState loading={!jobs.last && !jobs.error} error={jobs.error} reload={jobs.reload} label="os pedidos">
          {(jobs.last ?? []).length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há pedidos de cortes.</p> : (
            <div className="flex flex-col gap-3">
              {(jobs.last ?? []).map((j) => (
                <ClipJobCard key={j.id} j={j} access={access} mayExport={mayExport} mayRequest={mayRequest} retry={() => j.version_id && go(j.version_id, j.count)}
                  onDone={() => setTick((n) => n + 1)} />
              ))}
            </div>
          )}
        </LoadState>
      </section>
    </div>
  );
}

function ClipJobCard({ j, access, mayExport, mayRequest, retry, onDone }: {
  j: ClipJob; access: Access; mayExport: boolean; mayRequest: boolean; retry: () => void; onDone: () => void;
}) {
  const ws = access.ws;
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<PackageExportResult | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const failed = j.status === "failed" || j.status === "dead" || j.status === "cancelled";
  const exportAll = async () => {
    setBusy(true); setErr(null);
    try { setRes(await exportClips(access, j.id)); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const live = j.clips.filter((c) => c.active);
  const status = j.status === "running" ? "a procurar" : EXPORT_STATUS[j.status];
  return (
    <div className="rounded-lg border p-3 text-sm" aria-live="polite">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span><strong>{status}</strong> · {j.master_name ?? j.master_title ?? "vídeo"} · {j.count} cortes pedidos · {j.created_label}</span>
        <span className="text-xs text-muted-foreground">{new Date(j.created_at).toLocaleString("pt-PT", { timeZone: "Asia/Dubai" })}</span>
      </div>
      {j.status === "running" && <div className="mt-2 flex items-center gap-2"><Progress value={j.progress?.pct ?? 0} className="h-2 flex-1" /><span className="text-xs tabular-nums">{Math.round(j.progress?.pct ?? 0)}% · {j.progress?.step ?? ""}</span></div>}
      {j.status === "queued" && !j.worker_seen && <p className="mt-1 text-xs text-muted-foreground">O worker não está ligado agora: o pedido fica na fila e começa quando ele voltar.</p>}
      {j.last_error && j.status !== "done" && <p className="mt-1 text-xs text-destructive">{j.last_error}</p>}
      {failed && mayRequest && j.master_active && <Button size="sm" variant="outline" className="mt-2" onClick={retry}><RotateCwIcon /> Pedir outra vez</Button>}
      {!j.master_active && <p className="mt-1 text-xs text-amber-500">O vídeo longo deste pedido já não está ativo na Biblioteca.</p>}

      {j.status === "done" && (j.result?.flags?.length ?? 0) > 0 && (
        <ul className="mt-2 list-disc pl-5 text-xs text-amber-500">{j.result!.flags!.slice(0, 6).map((f) => <li key={f}>{f}</li>)}</ul>
      )}
      {j.status === "done" && (j.result?.blocked?.length ?? 0) > 0 && (
        <p className="mt-1 text-xs text-muted-foreground">{j.result!.blocked!.length} {j.result!.blocked!.length === 1 ? "candidato bloqueado" : "candidatos bloqueados"} pelo portão da dignidade (nunca viram corte).</p>
      )}

      {j.clips.length > 0 && (
        <div className="mt-3 overflow-x-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="text-left text-xs text-muted-foreground">
              <tr><th className="p-2">Pontuação</th><th className="p-2">Corte</th><th className="p-2">Máquina e etiquetas</th><th className="p-2">Riscos</th><th className="p-2">Exportação</th><th className="p-2" /></tr>
            </thead>
            <tbody>
              {j.clips.map((c) => (
                <tr key={c.idx} className="border-t align-top">
                  <td className="p-2 tabular-nums">{scoreText(c.meta.score)}</td>
                  <td className="p-2">
                    <p className="font-medium">{c.meta.title}</p>
                    <p className="text-xs text-muted-foreground">{clipTime(c.meta.times?.in)}–{clipTime(c.meta.times?.out)} · {Math.round(c.meta.times?.duration ?? 0)} s{c.meta.reordered ? " · gancho passado para o início" : ""}</p>
                    {c.meta.thesis && <p className="mt-1 text-xs">{c.meta.thesis}</p>}
                    {c.meta.justification && <p className="mt-1 text-xs text-muted-foreground">{c.meta.justification}</p>}
                  </td>
                  <td className="p-2 text-xs">
                    <p>{c.meta.machine ?? "—"}</p>
                    <p className="text-muted-foreground">{polemicText(c.meta.polemic)}{c.meta.identity_trigger ? ` · identidade: ${c.meta.identity_trigger}` : ""}</p>
                  </td>
                  <td className="p-2 text-xs">{(c.meta.risks ?? []).length ? <ul className="list-disc pl-4 text-amber-500">{c.meta.risks!.slice(0, 4).map((r) => <li key={r}>{r}</li>)}</ul> : <span className="text-muted-foreground">nenhum assinalado</span>}</td>
                  <td className="p-2 text-xs">{!c.active ? "no lixo" : c.export ? EXPORT_STATUS[c.export.status] : c.has_video ? "com vídeo" : "por exportar"}</td>
                  <td className="p-2 text-right">{c.active ? <Link className="underline" href={`/c/${ws}/editor?asset=${c.asset_id}`}>Abrir no editor</Link> : <Badge variant="outline">no lixo</Badge>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {j.status === "done" && j.clips.length === 0 && <p className="mt-2 text-xs text-muted-foreground">Não saiu nenhum corte válido deste vídeo.</p>}

      {j.status === "done" && live.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {mayExport && (
            <Button size="sm" onClick={exportAll} disabled={busy}>
              {busy ? <Loader2Icon className="animate-spin" /> : <ClapperboardIcon />} Exportar todos ({live.length})
            </Button>
          )}
          <Link className="text-xs underline" href={`/c/${ws}/revisao?ver=videos`}>Rever os exportados</Link>
          {!mayExport && <span className="text-xs text-muted-foreground">Exportar precisa da permissão de exportar vídeos.</span>}
        </div>
      )}
      {res && (
        <p className="mt-1 text-xs text-muted-foreground" role="status">
          {res.queued} {res.queued === 1 ? "corte na fila" : "cortes na fila"} para exportar. Cada um entra na revisão quando acabar, com as notas do QC.
          {res.failed.length > 0 && <span className="block text-destructive">Não deu para {res.failed.length}: {res.failed.slice(0, 3).map((f) => `${f.title} (${f.error})`).join("; ")}.</span>}
        </p>
      )}
      {err && <p className="mt-1 text-xs text-destructive" role="alert">{err} <button type="button" className="underline" onClick={exportAll}>Tentar de novo</button></p>}
    </div>
  );
}
