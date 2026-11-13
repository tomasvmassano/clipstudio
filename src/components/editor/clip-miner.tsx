"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { ClapperboardIcon, ExternalLinkIcon, Loader2Icon, RotateCwIcon, ScissorsIcon, UploadIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadState, useLoad } from "@/components/perf/perf-shared";
import { selectCls } from "@/components/media/media-shared";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { exportClips, listClips, requestClips, type ClipJob } from "@/lib/clips";
import { autoClipCount, bestMasterMatch, clipMasters, clipTime, momentText, polemicText, scoreText, youtubeId } from "@/lib/clips-format";
import { EXPORT_STATUS, type PackageExportResult } from "@/lib/edit-media";
import { fetchLibrary, uploadFile } from "@/lib/media";

const COUNTS = [3, 5, 8, 10, 12, 15, 20];

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
  const [count, setCount] = useState<number | null>(null);    // null = automático pela duração
  const [full, setFull] = useState(false);                    // modo completo (gancho no 0:00, título, CTA); por defeito leve
  const [yt, setYt] = useState("");
  const [ytInfo, setYtInfo] = useState<{ id: string; title: string | null; author: string | null; note: string | null } | null>(null);
  const [match, setMatch] = useState<string | null>(null);
  const [upload, setUpload] = useState<{ name: string; pct: number; phase: string; versionId?: string } | null>(null);
  const [goWhenReady, setGoWhenReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [over, setOver] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const ytId = youtubeId(yt);
  const picked = masters.find((a) => a.current?.id === version) ?? null;
  const dur = picked?.current?.media_info?.duration ?? null;

  const go = async (v = version, n: number | null = count, mode: "leve" | "completo" = full ? "completo" : "leve", link: string | null = ytId ? yt : null) => {
    setBusy(true); setErr(null);
    try { await requestClips(access, v, n, mode, link); setTick((x) => x + 1); setGoWhenReady(false); }
    catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };

  // link do YouTube: título pelo oEmbed e o ficheiro mais parecido da Biblioteca
  useEffect(() => {
    if (!ytId) return;
    let alive = true;
    const t = setTimeout(() => {
      fetch(`/api/clips/youtube?url=${encodeURIComponent(yt)}`, { cache: "no-store" })
        .then((r) => r.json())
        .then((b: { id?: string; title: string | null; author: string | null; note: string | null; error?: string }) => {
          if (!alive) return;
          if (!b.id) { setYtInfo(null); setErr(b.error ?? "Não deu para ler o link."); return; }
          setYtInfo({ id: b.id, title: b.title, author: b.author, note: b.note });
          const m = b.title ? bestMasterMatch(b.title, masters) : null;
          setMatch(m?.current?.id ?? null);
          if (m?.current) setVersion((v) => v || m.current!.id);
        })
        .catch(() => { if (alive) setYtInfo({ id: ytId, title: null, author: null, note: "O YouTube não respondeu: escolhe o ficheiro à mão." }); });
    }, 300);
    return () => { alive = false; clearTimeout(t); };
  }, [yt, ytId, masters]);

  // ficheiro carregado aqui: quando o servidor o der como pronto, fica escolhido (e pede, se já carregaste em Encontrar)
  const waiting = upload?.versionId && !masters.some((a) => a.current?.id === upload.versionId);
  useEffect(() => {
    if (!waiting) return;
    const id = setInterval(() => setTick((n) => n + 1), 8000);
    return () => clearInterval(id);
  }, [waiting]);
  const readyVid = upload?.versionId && masters.some((a) => a.current?.id === upload.versionId) ? upload.versionId : null;
  const goRef = useRef(go);
  useEffect(() => { goRef.current = go; });
  useEffect(() => {
    if (!readyVid) return;
    const t = setTimeout(() => {
      setVersion(readyVid); setUpload(null);
      if (goWhenReady) void goRef.current(readyVid);
    }, 0);
    return () => clearTimeout(t);
  }, [readyVid, goWhenReady]);

  const sendFile = async (f: File) => {
    if (!f.type.startsWith("video/")) { setErr(`${f.name} não é um vídeo.`); return; }
    setErr(null); setUpload({ name: f.name, pct: 0, phase: "a enviar" });
    try {
      const r = await uploadFile(access, f, { fields: { title: ytInfo?.title?.slice(0, 200) || f.name, kind: "video" } },
        (p) => setUpload((u) => (u ? { ...u, pct: p.total ? Math.round((p.loaded / p.total) * 100) : u.pct, phase: p.phase === "a_verificar" ? "a verificar" : "a enviar" } : u)));
      setUpload({ name: f.name, pct: 100, phase: "a verificar", versionId: r.versionId });
      setTick((n) => n + 1);
    } catch (e) { setUpload(null); setErr(`Não deu para carregar ${f.name}: ${(e as Error).message}`); }
  };

  const reason = !mayRequest ? "Sem permissão para procurar cortes." : waiting ? null : !version ? "Escolhe ou carrega o ficheiro do vídeo." : null;

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Cortes de vídeos longos</h1>
          <p className="text-sm text-muted-foreground">Cola o link do YouTube de um vídeo acabado e a IA encontra todos os momentos que dão um corte: conversas, reflexões, opiniões, histórias, momentos engraçados. Por defeito saem como foram ditos, só com legendas. A pontuação ordena os candidatos: não é uma previsão de visualizações.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setTick((n) => n + 1)}><RotateCwIcon /> Atualizar</Button>
      </div>

      {mayRequest && (
        <section className={over ? "rounded-xl border-2 border-dashed border-primary p-4" : "rounded-xl border p-4"} aria-labelledby="novo-pedido"
          onDragOver={(e) => { if (e.dataTransfer?.types.includes("Files")) { e.preventDefault(); setOver(true); } }}
          onDragLeave={() => setOver(false)}
          onDrop={(e) => { e.preventDefault(); setOver(false); const f = e.dataTransfer?.files?.[0]; if (f) void sendFile(f); }}>
          <h2 id="novo-pedido" className="mb-3 font-medium">Encontrar cortes</h2>
          <div className="flex flex-col gap-3">
            <label className="flex flex-col gap-1 text-sm">1. Link do YouTube
              <Input placeholder="https://www.youtube.com/watch?v=…" value={yt} onChange={(e) => { setYt(e.target.value); setYtInfo(null); setMatch(null); }} aria-label="Link do YouTube" />
              {yt && !ytId && <span className="text-xs text-destructive">Não parece um link de vídeo do YouTube.</span>}
              {ytInfo && (
                <span className="text-xs text-muted-foreground">
                  {ytInfo.title ? <>{ytInfo.title}{ytInfo.author ? ` · ${ytInfo.author}` : ""}. </> : null}
                  {ytInfo.note ?? (match ? "Encontrei o ficheiro na Biblioteca e escolhi-o." : "Não encontrei o ficheiro na Biblioteca: escolhe-o ou arrasta-o para aqui.")}
                </span>
              )}
            </label>
            <div className="flex flex-col gap-1 text-sm">
              <span>2. Ficheiro do vídeo <span className="text-xs text-muted-foreground">(o master; o YouTube não deixa descarregar, por isso o vídeo vem sempre do ficheiro)</span></span>
              {lib.error ? <LoadState loading={false} error={lib.error} reload={lib.reload} label="os vídeos">{null}</LoadState> : !lib.last ? <Skeleton className="h-9" /> : (
                <div className="flex flex-wrap items-center gap-2">
                  <select className={selectCls} value={version} onChange={(e) => setVersion(e.target.value)} aria-label="Ficheiro do vídeo">
                    <option value="">{masters.length ? "Escolher da Biblioteca…" : "Sem vídeos longos prontos na Biblioteca"}</option>
                    {masters.map((a) => <option key={a.id} value={a.current!.id}>{a.title !== a.current!.original_name ? `${a.title} · ` : ""}{a.current!.original_name ?? a.title}{a.current!.media_info?.duration ? ` · ${clipTime(a.current!.media_info.duration)}` : ""}</option>)}
                  </select>
                  <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()} disabled={!!upload}><UploadIcon /> Carregar ficheiro</Button>
                  <input ref={fileRef} type="file" accept="video/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void sendFile(f); }} />
                  <span className="text-xs text-muted-foreground">ou arrasta-o para esta caixa</span>
                </div>
              )}
              {upload && (
                <div className="flex items-center gap-2 text-xs">
                  <Progress value={upload.pct} className="h-2 w-40" />
                  <span>{upload.name} · {upload.phase === "a verificar" ? "a verificar no servidor (pode levar uns minutos)" : `${upload.pct}%`}</span>
                </div>
              )}
              <span className="text-xs text-muted-foreground">Sem o master? No YouTube Studio: Conteúdo → ⋮ → Transferir, e carrega aqui.</span>
            </div>
            <div className="flex flex-wrap items-center gap-4 text-sm">
              <label className="flex items-center gap-2">Cortes
                <select className={selectCls} value={count ?? ""} onChange={(e) => setCount(e.target.value ? Number(e.target.value) : null)} aria-label="Número de cortes">
                  <option value="">Automático{dur ? ` (${autoClipCount(dur)} para ${clipTime(dur)})` : " (~1 por 4 min)"}</option>
                  {COUNTS.map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </label>
              <label className="flex items-center gap-1.5"><input type="checkbox" checked={full} onChange={(e) => setFull(e.target.checked)} />
                Edição completa <span className="text-xs text-muted-foreground">(frase mais forte no início, título por cima e CTA; sem isto, só legendas)</span></label>
            </div>
          </div>
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <Button onClick={() => (waiting ? setGoWhenReady(true) : go())} disabled={!!reason || busy || goWhenReady}>
              {busy || goWhenReady ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />} {goWhenReady ? "Começa quando o ficheiro estiver pronto" : "Encontrar cortes"}
            </Button>
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
                <ClipJobCard key={j.id} j={j} access={access} mayExport={mayExport} mayRequest={mayRequest} retry={() => j.version_id && go(j.version_id, j.count, j.mode ?? "leve", j.youtube?.url ?? null)}
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
        <span><strong>{status}</strong> · {j.master_name ?? j.master_title ?? "vídeo"} · {j.count} cortes pedidos · {j.mode === "completo" ? "edição completa" : "só legendas"} · {j.created_label}
          {j.youtube?.url && <> · <a className="inline-flex items-center gap-0.5 underline" href={`https://www.youtube.com/watch?v=${j.youtube.id}`} target="_blank" rel="noreferrer">YouTube <ExternalLinkIcon className="size-3" /></a></>}</span>
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
              <tr><th className="p-2">Pontuação</th><th className="p-2">Corte</th><th className="p-2">Momento e etiquetas</th><th className="p-2">Riscos</th><th className="p-2">Exportação</th><th className="p-2" /></tr>
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
                    <p>{momentText(c.meta.moment)}{c.meta.machine && c.meta.machine !== "outra" ? ` · ${c.meta.machine}` : ""}</p>
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
