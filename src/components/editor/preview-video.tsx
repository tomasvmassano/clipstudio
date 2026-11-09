"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Access } from "@/lib/access";
import type { EditDoc } from "@/lib/edit-doc";
import { audioCam, DRIFT_S, shotAt, type Windows } from "@/lib/edit-preview";
import { fetchPreviewSources, proxyUrl, type PreviewSources } from "@/lib/edit-media";

/**
 * Imagem no palco do editor (EDL-08): um <video> por câmara com a versão leve (proxy) da gravação inteira, todos no mesmo
 * tempo da sessão; vê-se a câmara que o documento põe no ar e ouve-se a câmara do som. O relógio é o do editor (t):
 * o vídeo segue-o e só volta a posicionar quando se afasta mais de DRIFT_S (cortes, arrastar o cursor).
 * Sem proxies prontos devolve o estado por câmara e o palco continua só com cortes, legendas e hook.
 */
export function PreviewVideo({ access, asset, versionId, doc, t, playing }: {
  access: Access; asset: string; versionId: string | null; doc: EditDoc; t: number; playing: boolean;
}) {
  const [src, setSrc] = useState<PreviewSources | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [err, setErr] = useState<string | null>(null);
  const [reload, setReload] = useState(0);
  const refs = useRef<Record<string, HTMLVideoElement | null>>({});
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
        if (live) setUrls(Object.fromEntries(got));
      } catch (e) {
        if (live) setErr((e as Error).message);
      }
    })();
    return () => { live = false; };
  }, [access, asset, versionId, camsKey, reload]);

  const shot = useMemo(() => shotAt({ ...doc, source: { ...(doc as EditDoc & { source?: object }).source, windows: src?.windows ?? (doc as EditDoc & { source?: { windows?: Windows } }).source?.windows } } as EditDoc, t), [doc, t, src]);
  const sound = audioCam(doc);
  const offsets = ((doc as EditDoc & { source?: { offsets?: Record<string, number> } }).source?.offsets) ?? {};
  const offKey = JSON.stringify(offsets);
  const allReady = src && Object.keys(src.cams).length > 0 && Object.keys(src.cams).every((k) => urls[k]);

  useEffect(() => {
    if (!allReady) return;
    for (const [cam, v] of Object.entries(refs.current)) {
      if (!v) continue;
      if (!shot) { v.pause(); continue; }
      const want = Math.max(0, shot.session + (Number(offsets[cam]) || 0));   // cada câmara no seu tempo (desvio pelo som)
      if (Math.abs(v.currentTime - want) > (playing ? DRIFT_S : 0.04)) v.currentTime = want;
      v.muted = cam !== sound;
      if (playing && v.paused) void v.play().catch(() => { /* o browser pode recusar som sem gesto: fica em silêncio */ });
      if (!playing && !v.paused) v.pause();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allReady, shot, playing, sound, offKey]);

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
        <video key={cam} ref={(el) => { refs.current[cam] = el; }} src={url} playsInline preload="auto" muted={cam !== sound}
          onError={() => setReload((n) => n + 1)}
          className="absolute inset-0 h-full w-full object-cover transition-none"
          style={{ opacity: shot?.cam === cam ? 1 : 0, transform: `scale(${shot?.cam === cam ? shot.zoom : 1})` }} />
      ))}
    </div>
  );
}

function StageNote({ text }: { text: string }) {
  return <p className="absolute inset-x-2 bottom-2 rounded bg-black/60 px-2 py-1 text-center text-[11px] text-white/80" role="status">{text}</p>;
}
