"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { Access } from "@/lib/access";
import type { EditDoc } from "@/lib/edit-doc";
import { audioCam, audioRuns, runAt, shotAt, type Run, type Windows } from "@/lib/edit-preview";
import { audioUrl, fetchPreviewSources, proxyUrl, type PreviewSources } from "@/lib/edit-media";

/** Desvio tolerado entre a imagem e o som antes de reposicionar a imagem (s). Só a imagem, sem som, é reposicionada. */
const VIDEO_DRIFT_S = 0.3;
/** Um salto do cursor maior do que isto, a tocar, recomeça o som no sítio novo (s). */
const SEEK_JUMP_S = 0.3;

/**
 * Imagem e som no palco do editor (EDL-08; W10-29, ADR-0077). Um <video> por câmara com a versão leve da gravação inteira,
 * sempre sem som; o som vem de dois <audio> da câmara do som que se revezam. A tocar, é o som que dá o tempo ao editor
 * (onTime): só salta onde o corte salta (audioRuns), e o trecho seguinte fica posicionado no outro <audio> para a passagem
 * ser limpa. A imagem segue o som e só é reposicionada quando se afasta mais de VIDEO_DRIFT_S.
 * Parado, tudo segue o cursor do editor. Sem proxies prontos devolve o estado por câmara e o relógio fica no editor.
 */
export function PreviewVideo({ access, asset, versionId, doc, t, playing, onTime, onEnd, onDriving }: {
  access: Access; asset: string; versionId: string | null; doc: EditDoc; t: number; playing: boolean;
  /** O som manda no tempo enquanto toca. Sem isto o palco segue t como antes (sem som contínuo). */
  onTime?: (t: number) => void; onEnd?: () => void; onDriving?: (on: boolean) => void;
}) {
  const [src, setSrc] = useState<PreviewSources | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [subUrl, setSubUrl] = useState<string | null>(null);   // som substituto da câmara do som (W10-32)
  const [err, setErr] = useState<string | null>(null);
  const [reload, setReload] = useState(0);
  const refs = useRef<Record<string, HTMLVideoElement | null>>({});
  const audA = useRef<HTMLAudioElement | null>(null);
  const audB = useRef<HTMLAudioElement | null>(null);
  const camsKey = JSON.stringify((doc as EditDoc & { source?: { cams?: unknown } }).source?.cams ?? null);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const s = await fetchPreviewSources(access, asset, versionId);
        if (!live) return;
        setSrc(s); setErr(null);
        const ready = Object.entries(s.cams).filter(([, c]) => c.state === "pronta" && c.version_id);
        const got = await Promise.all(ready.map(async ([cam, c]) => [cam, (await proxyUrl(access, c.version_id!)).url] as const));
        const sub = s.cams[s.audio ?? ""]?.audio_version_id;
        const subU = sub ? (await audioUrl(access, sub)).url : null;
        if (live) { setUrls(Object.fromEntries(got)); setSubUrl(subU); }
      } catch (e) {
        if (live) setErr((e as Error).message);
      }
    })();
    return () => { live = false; };
  }, [access, asset, versionId, camsKey, reload]);

  const windows = src?.windows ?? (doc as EditDoc & { source?: { windows?: Windows } }).source?.windows;
  const docW = useMemo(() => ({ ...doc, source: { ...(doc as EditDoc & { source?: object }).source, windows } }) as EditDoc, [doc, windows]);
  const shot = useMemo(() => shotAt(docW, t), [docW, t]);
  const runs = useMemo(() => audioRuns(doc, windows), [doc, windows]);
  const sound = audioCam(doc);
  const offsets = ((doc as EditDoc & { source?: { offsets?: Record<string, number> } }).source?.offsets) ?? {};
  const offKey = JSON.stringify(offsets);
  const allReady = !!src && Object.keys(src.cams).length > 0 && Object.keys(src.cams).every((k) => urls[k]);
  // com som substituto, o palco ouve-o (o mesmo tempo da gravação); senão o som da versão leve da câmara
  const soundUrl = (src?.cams[sound]?.audio_version_id ? subUrl : null) ?? urls[sound] ?? null;
  const engine = !!onTime && allReady && !!soundUrl;

  // valores recentes para o ciclo de reprodução, sem o recomeçar a cada fotograma
  const live = useRef({ t, docW, offsets, onTime, onEnd, onDriving });
  useLayoutEffect(() => { live.current = { t, docW, offsets, onTime, onEnd, onDriving }; });

  // parado (ou sem motor de som): imagem no cursor; com motor o som está parado e a imagem não tem som
  useEffect(() => {
    if (!allReady || (engine && playing)) return;
    for (const [cam, v] of Object.entries(refs.current)) {
      if (!v) continue;
      if (!shot) { v.pause(); continue; }
      const want = Math.max(0, shot.session + (Number(offsets[cam]) || 0));
      if (Math.abs(v.currentTime - want) > (playing ? VIDEO_DRIFT_S : 0.04)) v.currentTime = want;
      v.muted = engine || cam !== sound;
      if (playing && v.paused) void v.play().catch(() => { /* sem gesto o browser pode recusar */ });
      if (!playing && !v.paused) v.pause();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allReady, engine, shot, playing, sound, offKey]);

  // a tocar com motor: o som dá o tempo
  useEffect(() => {
    if (!engine || !playing) return;
    const els = [audA.current, audB.current];
    if (!els[0] || !els[1] || !runs.length) return;
    const A = els as HTMLAudioElement[];
    const vids = refs.current;
    const soundOff = () => Number(live.current.offsets[sound]) || 0;
    const pos = (k: number, out: number) => Math.max(0, runs[k].sess + (out - runs[k].outStart) + soundOff());
    let act = 0, i = -1, raf = 0, stopped = false;
    let sent: number[] = [];                  // tempos que o próprio motor deu ao editor (os últimos ~4 s de fotogramas)
    live.current.onDriving?.(true);

    const prep = (k: number, el: HTMLAudioElement) => { if (k < runs.length) { el.pause(); el.currentTime = pos(k, runs[k].outStart); } };
    const videosTo = (out: number, force: boolean) => {
      const sh = shotAt(live.current.docW, out);
      for (const [cam, v] of Object.entries(refs.current)) {
        if (!v) continue;
        v.muted = true;
        if (!sh) { v.pause(); continue; }
        const want = Math.max(0, sh.session + (Number(live.current.offsets[cam]) || 0));
        if (force || (!v.seeking && Math.abs(v.currentTime - want) > VIDEO_DRIFT_S)) v.currentTime = want;
        if (v.paused) void v.play().catch(() => { /* imagem sem som: o browser deixa */ });
      }
    };
    const startAt = (out: number) => {
      i = runAt(runs, out);
      const r: Run = runs[i];
      const o = Math.min(Math.max(out, r.outStart), r.outEnd);
      A[1 - act].pause();
      A[act].currentTime = pos(i, o);
      prep(i + 1, A[1 - act]);
      void A[act].play().catch(() => { /* sem gesto não há som; o tempo continua pelo elemento */ });
      videosTo(o, true);
      sent = [o];
    };

    const tick = () => {
      if (stopped) return;
      // o cursor foi mudado à mão enquanto tocava: um tempo que o motor não deu (o React pode vir atrasado uns fotogramas)
      const ext = live.current.t;
      if (!sent.some((x) => Math.abs(x - ext) < SEEK_JUMP_S)) startAt(ext);
      const a = A[act];
      let r = runs[i];
      let out = r.outStart + (a.currentTime - soundOff() - r.sess);
      if (out >= r.outEnd - 0.012) {                                     // fim do trecho: passa para o outro <audio>
        if (i + 1 >= runs.length) {
          a.pause(); live.current.onTime?.(r.outEnd); live.current.onEnd?.();
          return;
        }
        const b = A[1 - act];
        void b.play().catch(() => { /* idem */ });
        a.pause();
        act = 1 - act; i += 1; r = runs[i];
        prep(i + 1, a);
        out = r.outStart;
        videosTo(out, true);                                             // a imagem salta com o som, no mesmo fotograma
      }
      out = Math.min(Math.max(out, r.outStart), r.outEnd);
      sent.push(out); if (sent.length > 240) sent = sent.slice(-240);
      live.current.onTime?.(out);
      videosTo(out, false);
      raf = requestAnimationFrame(tick);
    };

    startAt(live.current.t);
    raf = requestAnimationFrame(tick);
    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      live.current.onDriving?.(false);
      A.forEach((el) => el.pause());
      Object.values(vids).forEach((v) => v?.pause());
    };
  }, [engine, playing, runs, sound]);

  if (err) return <StageNote text={`Imagem indisponível: ${err}`} />;
  if (!src) return <StageNote text="A preparar a imagem…" />;
  if (!allReady) {
    const parts = Object.entries(src.cams).map(([cam, c]) => `${cam}: ${c.state === "em_falta" ? `falta carregar ${src.names?.[cam] ?? "a gravação"} na Biblioteca`
      : c.state === "pendente" ? "a preparar a versão leve" : c.state === "falhou" ? "a versão leve falhou (refaz na Biblioteca)" : c.state === "pronta" ? "a abrir" : "sem versão leve"}`);
    return <StageNote text={`Sem imagem ainda · ${parts.join(" · ") || "o documento não tem câmaras"}`} />;
  }
  return (
    <div className="absolute inset-0 overflow-hidden bg-black" aria-hidden="true">
      {Object.entries(urls).map(([cam, url]) => (
        <video key={cam} ref={(el) => { refs.current[cam] = el; }} src={url} playsInline preload="auto" muted={engine || cam !== sound}
          onError={() => setReload((n) => n + 1)}
          className="absolute inset-0 h-full w-full object-cover transition-none"
          // zoom à volta do ponto de enquadramento: o render corta (iw - W)·x, que é escalar com transform-origin em x (e y)
          style={{ opacity: shot?.cam === cam ? 1 : 0, transform: `scale(${shot?.cam === cam ? shot.zoom : 1})`,
            transformOrigin: shot?.cam === cam ? `${shot.x * 100}% ${shot.y * 100}%` : "50% 38%" }} />
      ))}
      {engine && soundUrl && (
        <>
          <audio ref={audA} src={soundUrl} preload="auto" onError={() => setReload((n) => n + 1)} />
          <audio ref={audB} src={soundUrl} preload="auto" onError={() => setReload((n) => n + 1)} />
        </>
      )}
    </div>
  );
}

function StageNote({ text }: { text: string }) {
  return <p className="absolute inset-x-2 bottom-2 rounded bg-black/60 px-2 py-1 text-center text-[11px] text-white/80" role="status">{text}</p>;
}
