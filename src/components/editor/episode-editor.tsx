"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { DownloadIcon, Loader2Icon, MicIcon, PlusIcon, RotateCwIcon, Trash2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadState, useLoad } from "@/components/perf/perf-shared";
import { selectCls } from "@/components/media/media-shared";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { episodeFileUrl, listEpisodes, requestEpisode, type EpisodeJob } from "@/lib/episodes";
import { camsPayload, camsProblem, durText, FILE_LABEL, parseProfile, reasonRows, summaryLine, type CamRow } from "@/lib/episodes-format";
import { fetchLibrary } from "@/lib/media";

const STATUS: Record<EpisodeJob["status"], string> = {
  queued: "na fila", running: "a editar", done: "pronto", failed: "falhou", dead: "falhou", cancelled: "cancelado",
};

/** Edição do episódio completo (POD-01..06, CHG-013): escolher câmaras, pedir, ver o job real, descarregar o resultado. */
export function EpisodeEditorView({ access }: { access: Access }) {
  const { can } = useSession();
  const mayRequest = can("edit.episode");
  const mayDownload = can("media.download");
  const [tick, setTick] = useState(0);
  const lib = useLoad(() => fetchLibrary(access, { kind: "video", limit: 200 }), `${access.ws}:lib:${tick}`);
  const jobs = useLoad(() => listEpisodes(access), `${access.ws}:episodes:${tick}`);
  const active = (jobs.last ?? []).some((j) => j.status === "queued" || j.status === "running");
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setTick((n) => n + 1), 8000);
    return () => clearInterval(id);
  }, [active]);

  const videos = useMemo(() => (lib.last?.assets ?? []).filter((a) => {
    const v = a.current;
    if (!v || v.storage !== "r2" || v.state !== "pronta" || !(v.mime ?? "").startsWith("video/")) return false;
    if (a.tags.includes("corte") || a.tags.includes("pacote") || a.tags.includes("episodio")) return false;
    const d = v.media_info?.duration;
    return d == null || (d >= 60 && d <= 4 * 3600);
  }), [lib.last]);
  const [rows, setRows] = useState<CamRow[]>([{ name: "frente", version: "" }]);
  const [audio, setAudio] = useState("");
  const [wide, setWide] = useState("");
  const [lang, setLang] = useState<"" | "pt" | "en">("");
  const [profileText, setProfileText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const names = rows.filter((r) => r.version).map((r) => r.name.trim());
  const prof = parseProfile(profileText);
  const problem = !mayRequest ? "Sem permissão para editar episódios." : camsProblem(rows, audio, wide) ?? prof.error;

  const setRow = (i: number, p: Partial<CamRow>) => setRows((rs) => rs.map((r, k) => (k === i ? { ...r, ...p } : r)));
  const go = async () => {
    setBusy(true); setErr(null);
    try {
      await requestEpisode(access, camsPayload(rows), audio || names[0] || null, wide || null, prof.profile, lang || null);
      setTick((x) => x + 1);
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Edição de episódios</h1>
          <p className="text-sm text-muted-foreground">O episódio completo de um podcast ou vídeo longo, limpo pela IA: pausas acima do que o estilo permite, hesitações, gaguez, repetições, falsos arranques e conversa antes e depois; câmara de quem está a falar; som ao nível do estilo. Sai o master, o áudio, as legendas, os capítulos e as notas. Cada corte tem o motivo. O original nunca é alterado.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setTick((n) => n + 1)}><RotateCwIcon /> Atualizar</Button>
      </div>

      {mayRequest && (
        <section className="rounded-xl border p-4" aria-labelledby="novo-episodio">
          <h2 id="novo-episodio" className="mb-3 font-medium">Editar um episódio</h2>
          {lib.error ? <LoadState loading={false} error={lib.error} reload={lib.reload} label="os vídeos">{null}</LoadState> : !lib.last ? <Skeleton className="h-24" /> : (
            <div className="flex flex-col gap-3 text-sm">
              <span>1. Câmaras <span className="text-xs text-muted-foreground">(uma por gravação; os vídeos têm de estar prontos na Biblioteca. Com várias, sincronizo pelo som.)</span></span>
              {videos.length === 0 && <p className="text-xs text-muted-foreground">Sem vídeos prontos na Biblioteca (de 1 minuto a 4 horas). Carrega as gravações na <Link className="underline" href={`/c/${access.ws}/biblioteca`}>Biblioteca</Link>.</p>}
              {rows.map((r, i) => (
                <div key={i} className="flex flex-wrap items-center gap-2">
                  <Input className="w-36" value={r.name} onChange={(e) => setRow(i, { name: e.target.value.toLowerCase() })} aria-label={`Nome da câmara ${i + 1}`} placeholder="ex.: frente" />
                  <select className={selectCls} value={r.version} onChange={(e) => setRow(i, { version: e.target.value })} aria-label={`Vídeo da câmara ${i + 1}`}>
                    <option value="">Escolher da Biblioteca…</option>
                    {videos.map((a) => <option key={a.id} value={a.current!.id}>{a.current!.original_name ?? a.title}{a.current!.media_info?.duration ? ` · ${durText(a.current!.media_info.duration)}` : ""}</option>)}
                  </select>
                  {rows.length > 1 && <Button size="icon" variant="ghost" onClick={() => setRows((rs) => rs.filter((_, k) => k !== i))} aria-label={`Tirar a câmara ${i + 1}`}><Trash2Icon /></Button>}
                </div>
              ))}
              {rows.length < 4 && <Button size="sm" variant="outline" className="self-start" onClick={() => setRows((rs) => [...rs, { name: ["convidado", "largo", "extra"][rs.length - 1] ?? `cam${rs.length + 1}`, version: "" }])}><PlusIcon /> Câmara</Button>}
              <div className="flex flex-wrap items-center gap-4">
                <label className="flex items-center gap-2">2. Som de
                  <select className={selectCls} value={audio} onChange={(e) => setAudio(e.target.value)} aria-label="Câmara do som">
                    <option value="">{names[0] ? `${names[0]} (a primeira)` : "a primeira câmara"}</option>
                    {names.map((n) => <option key={n} value={n}>{n}</option>)}
                  </select>
                </label>
                {names.length > 1 && (
                  <label className="flex items-center gap-2">Plano largo
                    <select className={selectCls} value={wide} onChange={(e) => setWide(e.target.value)} aria-label="Câmara do plano largo">
                      <option value="">nenhum</option>
                      {names.map((n) => <option key={n} value={n}>{n}</option>)}
                    </select>
                  </label>
                )}
                <label className="flex items-center gap-2">Idioma
                  <select className={selectCls} value={lang} onChange={(e) => setLang(e.target.value as "" | "pt" | "en")} aria-label="Idioma">
                    <option value="">detetar</option><option value="pt">português</option><option value="en">inglês</option>
                  </select>
                </label>
              </div>
              <label className="flex flex-col gap-1">3. Perfil do estilo <span className="text-xs text-muted-foreground">(opcional: o perfil aprendido de episódios já editados, em JSON; sem perfil uso o defeito para podcast e digo-o no resultado)</span>
                <textarea className="min-h-16 rounded-md border bg-transparent p-2 font-mono text-xs" value={profileText} onChange={(e) => setProfileText(e.target.value)} aria-label="Perfil do estilo (JSON)" placeholder='{"pacing": {"max_pause_s": 0.6}, "audio": {"lufs": -16}}' />
              </label>
            </div>
          )}
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <Button onClick={go} disabled={!!problem || busy}>{busy ? <Loader2Icon className="animate-spin" /> : <MicIcon />} Editar episódio</Button>
            {problem && <span className="text-xs text-muted-foreground">{problem}</span>}
          </div>
          <p className="mt-2 text-xs text-muted-foreground">O master sai em paisagem e entra na Biblioteca como vídeo novo. Ainda não abre no editor (que é vertical): descarrega e revê. Os cortes para redes saem depois deste master, em Cortes de vídeos longos.</p>
          {err && <p className="mt-2 text-sm text-destructive" role="alert">{err}</p>}
        </section>
      )}

      <section aria-labelledby="episodios">
        <h2 id="episodios" className="mb-2 font-medium">Episódios</h2>
        <LoadState loading={!jobs.last && !jobs.error} error={jobs.error} reload={jobs.reload} label="os episódios">
          {(jobs.last ?? []).length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há episódios editados.</p> : (
            <div className="flex flex-col gap-3">
              {(jobs.last ?? []).map((j) => <EpisodeCard key={j.id} j={j} access={access} mayDownload={mayDownload} />)}
            </div>
          )}
        </LoadState>
      </section>
    </div>
  );
}

function EpisodeCard({ j, access, mayDownload }: { j: EpisodeJob; access: Access; mayDownload: boolean }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const line = summaryLine(j.summary);
  const pct = typeof j.progress?.pct === "number" ? Math.max(0, Math.min(100, j.progress.pct)) : null;
  const down = async (name: EpisodeJob["files"][number]) => {
    setBusy(name); setErr(null);
    try { window.location.assign(await episodeFileUrl(access, j.id, name)); }
    catch (e) { setErr((e as Error).message); } finally { setBusy(null); }
  };
  return (
    <article className="rounded-xl border p-4 text-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="font-medium">{j.title ?? "Episódio"}</div>
        <Badge variant={j.status === "done" ? "default" : j.status === "failed" || j.status === "dead" ? "destructive" : "secondary"}>{STATUS[j.status]}</Badge>
      </div>
      <p className="text-xs text-muted-foreground">
        {Object.entries(j.cams ?? {}).map(([k, v]) => `${k}: ${v}`).join(" · ")}{j.wide ? ` · largo: ${j.wide}` : ""} · {j.profile ? "com perfil do estilo" : "perfil por defeito"} · {j.created_label ?? ""} · {new Date(j.created_at).toLocaleString("pt-PT")}
      </p>
      {(j.status === "queued" || j.status === "running") && (
        <div className="mt-2 flex items-center gap-2 text-xs"><Progress value={pct ?? 0} className="h-2 w-48" /><span>{j.progress?.step ?? (j.status === "queued" ? "na fila do worker" : "a começar")}{pct != null ? ` · ${Math.round(pct)}%` : ""}</span></div>
      )}
      {(j.status === "failed" || j.status === "dead") && <p className="mt-2 text-xs text-destructive">{j.last_error ?? "Falhou sem motivo registado."} Volta a pedir com as mesmas câmaras para tentar de novo.</p>}
      {j.status === "done" && (
        <div className="mt-3 flex flex-col gap-2">
          {line && <p>{line}</p>}
          {reasonRows(j.summary).length > 0 && <p className="text-xs text-muted-foreground">{reasonRows(j.summary).map(([k, v]) => `${k} ${v}`).join(" · ")}</p>}
          {j.summary?.warning && <p className="text-xs text-amber-600">{j.summary.warning}</p>}
          {(j.flags ?? []).filter((f) => f !== j.summary?.warning).map((f) => <p key={f} className="text-xs text-muted-foreground">⚑ {f}</p>)}
          {(j.titles ?? []).length > 0 && <div className="text-xs"><span className="text-muted-foreground">Títulos: </span>{(j.titles ?? []).join(" · ")}</div>}
          <div className="flex flex-wrap gap-2">
            {j.files.filter((f) => f in FILE_LABEL).map((f) => (
              <Button key={f} size="sm" variant="outline" disabled={!mayDownload || !!busy} onClick={() => down(f)} title={mayDownload ? undefined : "Sem permissão para descarregar"}>
                {busy === f ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} {FILE_LABEL[f]}
              </Button>
            ))}
            {j.master_asset_id && <Button size="sm" variant="ghost" render={<Link href={`/c/${access.ws}/biblioteca?asset=${j.master_asset_id}`} />} nativeButton={false}>Ver na Biblioteca</Button>}
          </div>
          {err && <p className="text-xs text-destructive" role="alert">{err}</p>}
        </div>
      )}
    </article>
  );
}
