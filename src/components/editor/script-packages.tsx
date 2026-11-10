"use client";

import { CAP_STYLES } from "@/lib/caption-plan";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { ClapperboardIcon, Link2Icon, Loader2Icon, RotateCwIcon, SparklesIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { useLoad } from "@/components/perf/perf-shared";
import { selectCls } from "@/components/media/media-shared";
import type { Access } from "@/lib/access";
import { fetchGuioes, todayDubai } from "@/lib/data";
import { EXPORT_STATUS, exportPackage, type PackageExportResult } from "@/lib/edit-media";
import { fetchLibrary } from "@/lib/media";
import {
  CAMERA_LABEL, ROW_STATE_LABEL, autoReasonLabel, linkClip, listScriptPackages, requestScriptPackage, rowState, saveScriptSettings,
  type Camera, type ClipLink, type ScriptList, type ScriptRow,
} from "@/lib/package-script";
import type { Guiao } from "@/lib/types";

const STYLES = (["S15", "S14", "S17"] as const).map((id) => ({ id, label: CAP_STYLES[id].label }));   // os estilos que o render desenha
const code = (e: unknown) => (e as { code?: string } | null)?.code;
const gLabel = (g: { n: number; date: string; tema: string | null }) => `${g.date.slice(8, 10)}/${g.date.slice(5, 7)} · ${String(g.n).padStart(2, "0")} ${g.tema ?? "sem tema"}`;

/**
 * Pacote por guião (STU-03, ADR-0070): gravações curtas de cada guião (frente + lado) ligadas na Biblioteca ou no envio; o
 * pacote de cada guião pede-se aqui ou corre sozinho quando chegam as duas (definição do cliente). Servidor decide tudo.
 */
export function ScriptPackagesSection({ access }: { access: Access }) {
  const [tick, setTick] = useState(0);
  const list = useLoad(() => listScriptPackages(access), `${access.ws}:ps:${tick}`);
  const d = list.last;
  const active = (d?.scripts ?? []).some((r) => r.job?.status === "queued" || r.job?.status === "running"
    || r.front?.state === "pendente" || r.side?.state === "pendente"
    || r.job?.outputs.some((o) => o.export?.status === "queued" || o.export?.status === "running"));
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setTick((n) => n + 1), 8000);
    return () => clearInterval(id);
  }, [active]);
  const refresh = () => setTick((n) => n + 1);

  return (
    <section className="flex min-w-0 flex-col gap-4 rounded-xl border p-4" aria-labelledby="por-guiao">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 id="por-guiao" className="font-medium">Pacote por guião</h2>
          <p className="text-sm text-muted-foreground">Cada guião com a sua gravação curta (câmara da frente + câmara do lado com o som). O pacote de um guião fica pronto poucos minutos depois de as duas chegarem, sem esperar pela sessão inteira.</p>
        </div>
        <Button variant="outline" size="sm" onClick={refresh}><RotateCwIcon /> Atualizar</Button>
      </div>
      {list.error ? (
        <Alert variant={code(list.error) === "42501" ? "default" : "destructive"} role="alert">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>{code(list.error) === "42501" ? "Não tens acesso ao pacote por guião deste cliente." : `Não consegui carregar os pacotes por guião: ${(list.error as Error).message}`}</span>
            {code(list.error) !== "42501" && <Button size="sm" variant="outline" onClick={list.reload}><RotateCwIcon /> Tentar de novo</Button>}
          </AlertDescription>
        </Alert>
      ) : !d ? <Skeleton className="h-40" /> : (
        <>
          <SettingsCard key={`${d.settings.updated_at}`} access={access} d={d} onSaved={refresh} />
          {d.can.link && <LinkForm access={access} onDone={refresh} />}
          {d.scripts.length === 0 ? (
            <p className="text-sm text-muted-foreground">Ainda não há gravações ligadas a guiões. Liga-as acima, no envio da <Link className="underline" href={`/c/${access.ws}/biblioteca`}>Biblioteca</Link> ou na ficha de cada ficheiro.</p>
          ) : (
            <ul className="flex flex-col gap-2">{d.scripts.map((r) => <ScriptRowView key={r.guiao.id} r={r} d={d} access={access} onDone={refresh} />)}</ul>
          )}
        </>
      )}
    </section>
  );
}

function SettingsCard({ access, d, onSaved }: { access: Access; d: ScriptList; onSaved: () => void }) {
  const s = d.settings;
  const [autoPkg, setAutoPkg] = useState(s.auto_package);
  const [autoExp, setAutoExp] = useState(s.auto_export);
  const [style, setStyle] = useState(s.style);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const dirty = autoPkg !== s.auto_package || autoExp !== s.auto_export || style !== s.style;
  const save = async () => {
    setBusy(true); setErr(null); setSaved(false);
    try { await saveScriptSettings(access, { auto_package: autoPkg, auto_export: autoExp, style }); setSaved(true); onSaved(); }
    catch (e) { setErr(code(e) === "42501" ? "Sem permissão: precisa de gerir estilos (e de exportar, para o exportar automático)." : (e as Error).message); }
    finally { setBusy(false); }
  };
  const on = s.auto_package || s.auto_export;
  return (
    <div className="rounded-md border p-3 text-sm">
      <h3 className="mb-2 font-medium">Automático</h3>
      {on && s.delegate_ok === false && (
        <Alert className="mb-2" role="alert"><AlertDescription>O automático está parado: {s.enabled_label ?? "quem o ligou"} já não tem permissão (ou a funcionalidade) para o correr. Grava as definições outra vez com a tua conta para o retomar.</AlertDescription></Alert>
      )}
      {d.can.settings ? (
        <div className="flex flex-col gap-2">
          <label className="flex items-start gap-2"><input type="checkbox" className="mt-1" checked={autoPkg} onChange={(e) => setAutoPkg(e.target.checked)} />
            <span>Criar o pacote de cada guião quando as duas gravações chegam</span></label>
          <label className="flex items-start gap-2"><input type="checkbox" className="mt-1" checked={autoExp} disabled={!d.can.export} onChange={(e) => setAutoExp(e.target.checked)} />
            <span>Exportar todos os vídeos do guião quando o pacote acaba (entram na revisão em lote){!d.can.export && <span className="block text-xs text-muted-foreground">Precisa da permissão de exportar vídeos.</span>}</span></label>
          <label className="flex max-w-xs flex-col gap-1">Estilo de legendas
            <select className={selectCls} value={style} onChange={(e) => setStyle(e.target.value)}>
              {!STYLES.some((x) => x.id === style) && <option value={style}>{style}</option>}
              {STYLES.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
            </select>
          </label>
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" onClick={save} disabled={!dirty || busy}>{busy && <Loader2Icon className="animate-spin" />} Gravar</Button>
            {saved && !dirty && <span className="text-xs text-muted-foreground" role="status">Gravado.</span>}
            {(autoPkg || autoExp) && <span className="text-xs text-muted-foreground">O automático corre em nome de quem grava estas definições.</span>}
          </div>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
        </div>
      ) : (
        <p className="text-muted-foreground">{s.auto_package ? "O pacote de cada guião é criado sozinho quando chegam as duas gravações" : "O pacote de cada guião pede-se à mão"}{s.auto_export ? " e os vídeos são exportados sozinhos" : ""}. Estilo {s.style}.{s.updated_label ? ` Definido por ${s.updated_label}.` : ""}</p>
      )}
    </div>
  );
}

/** Ligar um vídeo da Biblioteca a um guião e a uma câmara. Com `asset` fixo (ficha do ficheiro) só escolhe guião e câmara. */
export function LinkForm({ access, asset, current, onDone }: { access: Access; asset?: string; current?: ClipLink | null; onDone: () => void }) {
  const lib = useLoad(() => (asset ? Promise.resolve(null) : fetchLibrary(access, { kind: "video", limit: 200 })), `${access.ws}:lk:${asset ?? ""}`);
  const gui = useLoad(() => fetchGuioes(access, todayDubai(), 10), `${access.ws}:lkg`);
  const videos = useMemo(() => (lib.last?.assets ?? []).filter((a) => a.lifecycle === "ativo" && !a.tags.includes("pacote")
    && (a.current?.storage === "r2" || a.pending)), [lib.last]);
  const guioes = useMemo(() => sortGuioes(gui.last ?? []), [gui.last]);
  const [file, setFile] = useState(asset ?? "");
  const [guiao, setGuiao] = useState(current?.content_id ?? "");
  const [camera, setCamera] = useState<Camera | "">(current?.camera ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const go = async () => {
    setBusy(true); setErr(null); setDone(null);
    try {
      const r = await linkClip(access, file, guiao, camera as Camera, "biblioteca");
      setDone(r.repeated ? "Já estava ligado." : "Ligado.");
      if (!asset) setFile("");
      onDone();
    } catch (e) { setErr(code(e) === "42501" ? "Sem permissão para mudar ficheiros da Biblioteca." : (e as Error).message); }
    finally { setBusy(false); }
  };
  const loadErr = lib.error ?? gui.error;
  return (
    <form className="rounded-md border p-3 text-sm" onSubmit={(e) => { e.preventDefault(); void go(); }} aria-label="Ligar gravação a um guião">
      {!asset && <h3 className="mb-2 font-medium">Ligar uma gravação a um guião</h3>}
      {loadErr ? (
        <p className="text-destructive" role="alert">Não consegui carregar {lib.error ? "os vídeos" : "os guiões"}: {(loadErr as Error).message}{" "}
          <button type="button" className="underline" onClick={() => { lib.reload(); gui.reload(); }}>Tentar de novo</button></p>
      ) : (!asset && !lib.last) || !gui.last ? <Skeleton className="h-10" /> : (
        <div className="grid gap-2 md:grid-cols-[1fr_1fr_auto_auto] md:items-end">
          {!asset && (
            <label className="flex min-w-0 flex-col gap-1">Gravação
              <select className={selectCls} value={file} onChange={(e) => setFile(e.target.value)}>
                <option value="">Escolher…</option>
                {videos.map((a) => <option key={a.id} value={a.id}>{a.current?.original_name ?? a.pending?.original_name ?? a.title}</option>)}
              </select>
            </label>
          )}
          <label className="flex min-w-0 flex-col gap-1">Guião
            <select className={selectCls} value={guiao} onChange={(e) => setGuiao(e.target.value)}>
              <option value="">Escolher…</option>
              {guioes.map((g) => <option key={g.id} value={g.id}>{gLabel(g)}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">Câmara
            <select className={selectCls} value={camera} onChange={(e) => setCamera(e.target.value as Camera | "")}>
              <option value="">Escolher…</option>
              {(Object.keys(CAMERA_LABEL) as Camera[]).map((c) => <option key={c} value={c}>{CAMERA_LABEL[c]}</option>)}
            </select>
          </label>
          <Button type="submit" size="sm" disabled={!file || !guiao || !camera || busy}>{busy ? <Loader2Icon className="animate-spin" /> : <Link2Icon />} Ligar</Button>
        </div>
      )}
      {!asset && lib.last && videos.length === 0 && <p className="mt-1 text-xs text-muted-foreground">Sem vídeos no armazenamento de vídeo (R2) desta Biblioteca.</p>}
      {done && <p className="mt-1 text-xs text-muted-foreground" role="status">{done}</p>}
      {err && <p className="mt-1 text-sm text-destructive" role="alert">{err}</p>}
    </form>
  );
}

function sortGuioes(gs: Guiao[]) {
  return [...gs].filter((g) => g.editorial_status !== "archived" && g.editorial_status !== "rejected")
    .sort((a, b) => (a.date === b.date ? a.n - b.n : a.date < b.date ? 1 : -1));
}

function ClipCell({ cam, c }: { cam: Camera; c: ClipLink | null }) {
  const state = !c ? "em falta" : c.state === "pronta" ? (c.storage === "r2" ? "pronta" : "fora do R2") : c.state === "pendente" ? "a verificar" : c.state === "falhou" ? "falhou" : c.state === "apagada" ? "apagada" : "sem ficheiro";
  return (
    <span className="min-w-0">
      <span className="text-muted-foreground">{CAMERA_LABEL[cam]}:</span>{" "}
      {c ? <span className="break-all">{c.name ?? c.title}</span> : null} <Badge variant={c?.state === "pronta" && c.storage === "r2" ? "outline" : "secondary"}>{state}</Badge>
    </span>
  );
}

function ScriptRowView({ r, d, access, onDone }: { r: ScriptRow; d: ScriptList; access: Access; onDone: () => void }) {
  const ws = access.ws;
  const st = rowState(r);
  const j = r.job;
  const [busy, setBusy] = useState<"" | "pkg" | "exp">("");
  const [err, setErr] = useState<string | null>(null);
  const [exp, setExp] = useState<PackageExportResult | null>(null);
  const request = async () => {
    setBusy("pkg"); setErr(null);
    try { await requestScriptPackage(access, r.guiao.id); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(""); }
  };
  const exportAll = async () => {
    if (!j) return;
    setBusy("exp"); setErr(null);
    try { setExp(await exportPackage(access, j.id)); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(""); }
  };
  const canRequest = d.can.request && (st === "pronto_para_pacote" || st === "pacote_falhou");
  const reason = autoReasonLabel(r.auto?.reason);
  const notExported = j?.outputs.filter((o) => !o.export || ["failed", "dead", "cancelled"].includes(o.export.status)).length ?? 0;
  return (
    <li className="rounded-md border p-3 text-sm" aria-live="polite">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <strong className="min-w-0">{gLabel(r.guiao)}</strong>
        <Badge variant={st === "pacote_falhou" || st === "gravacao_falhou" ? "destructive" : "outline"}>{ROW_STATE_LABEL[st]}</Badge>
      </div>
      <div className="mt-1 flex flex-col gap-1 sm:flex-row sm:flex-wrap sm:gap-4">
        <ClipCell cam="front" c={r.front} /><ClipCell cam="side" c={r.side} />
      </div>
      {j && st === "a_preparar" && (
        <div className="mt-2 flex items-center gap-2"><Progress value={j.progress?.pct ?? 0} className="h-2 flex-1" aria-label="Progresso do pacote" /><span className="text-xs tabular-nums">{Math.round(j.progress?.pct ?? 0)}% · {j.progress?.step ?? ""}</span></div>
      )}
      {j && st === "na_fila" && !j.worker_seen && <p className="mt-1 text-xs text-muted-foreground">O worker não está ligado agora: o pedido fica na fila e começa quando ele voltar.</p>}
      {j && st === "pacote_falhou" && j.last_error && <p className="mt-1 text-xs text-destructive">{j.last_error}</p>}
      {j && st === "pacote_pronto" && (j.result?.missing?.length ?? 0) > 0 && <p className="mt-1 text-xs text-amber-500">Não encontrei este guião na gravação{j.result?.flags?.length ? `: ${j.result.flags.slice(0, 2).join(" · ")}` : "."}</p>}
      {reason && !(j && j.id === r.auto?.job_id) && st !== "pacote_pronto" && <p className="mt-1 text-xs text-amber-500">O automático não correu: {reason}.</p>}
      {j && st === "pacote_pronto" && j.outputs.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1">
          {j.outputs.map((o) => (
            <Link key={o.asset_id} className="rounded border px-2 py-0.5 text-xs hover:bg-muted" href={`/c/${ws}/editor?asset=${o.asset_id}`}>
              Hook {o.hook}{o.export ? ` · ${EXPORT_STATUS[o.export.status]}` : ""}
            </Link>
          ))}
        </div>
      )}
      <div className="mt-2 flex flex-wrap items-center gap-2">
        {canRequest && (
          <Button size="sm" variant={st === "pacote_falhou" ? "default" : "outline"} onClick={request} disabled={busy !== ""}>
            {busy === "pkg" ? <Loader2Icon className="animate-spin" /> : <SparklesIcon />} {st === "pacote_falhou" ? "Tentar de novo" : "Criar pacote deste guião"}
          </Button>
        )}
        {j && st === "pacote_pronto" && j.outputs.length > 0 && d.can.export && notExported > 0 && (
          <Button size="sm" onClick={exportAll} disabled={busy !== ""}>
            {busy === "exp" ? <Loader2Icon className="animate-spin" /> : <ClapperboardIcon />} Exportar todos ({notExported})
          </Button>
        )}
        {j && st === "pacote_pronto" && j.outputs.length > 0 && <Link className="text-xs underline" href={`/c/${ws}/revisao?ver=videos`}>Rever os exportados</Link>}
        {j && <span className="text-xs text-muted-foreground">{j.origin === "auto" ? "automático" : "pedido"} por {j.created_label ?? "?"}</span>}
      </div>
      {exp && <p className="mt-1 text-xs text-muted-foreground" role="status">{exp.queued} {exp.queued === 1 ? "vídeo na fila" : "vídeos na fila"} para exportar.{exp.failed.length > 0 && <span className="block text-destructive">Não deu para {exp.failed.length}: {exp.failed.slice(0, 3).map((f) => `${f.title} (${f.error})`).join("; ")}.</span>}</p>}
      {err && <p className="mt-1 text-sm text-destructive" role="alert">{err}</p>}
    </li>
  );
}
