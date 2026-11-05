"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ExternalLinkIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import type { Access } from "@/lib/access";
import { dayTitle } from "@/lib/calendar";
import { fetchRecordOptions, recordPublished, type Publication, type RecordOptions } from "@/lib/pub";
import { PLATFORM_LABEL, RECORD_BLOCKED_LABEL } from "@/lib/pub-rules";
import { parsePostUrl, postUrlProblem, POST_URL_HINT } from "@/lib/pub-url";
import { fromLocalInput, toLocalInput } from "@/lib/tasks";
import { WsLink } from "@/components/ws-link";

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm";
const variantName = (v: string) => (v.startsWith("hook_") ? `Hook ${v.slice(5)}` : "Geral");

type Props = {
  access: Access;
  /** A partir do calendário: a publicação aprovada (ou já publicada, para corrigir). */
  publicationId?: string | null;
  /** A partir da revisão: a versão do vídeo aprovada. */
  versionId?: string | null;
  onClose: () => void;
  onDone: (msg: string) => void;
};

/**
 * Registar uma publicação feita à mão (FR-12-02, ADR-0054): link do post, hora, vídeo aprovado e conta da publicação aprovada.
 * A app não publica nada. O servidor volta a verificar tudo (aprovação, versão atual aprovada, URL da plataforma, duplicados)
 * e grava a linhagem para as métricas ficarem nesta publicação. Corrigir um registo exige motivo.
 */
export function RecordPublicationDialog({ access, publicationId = null, versionId = null, onClose, onDone }: Props) {
  const [opts, setOpts] = useState<RecordOptions | null>(null);
  const [loadErr, setLoadErr] = useState("");
  const [tick, setTick] = useState(0);
  const [pubId, setPubId] = useState(publicationId ?? "");
  const [videoId, setVideoId] = useState(versionId ?? "");
  const [url, setUrl] = useState("");
  const [at, setAt] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [nowMs, setNowMs] = useState(0);   // quando as opções chegaram: o servidor volta a verificar a hora

  const load = useCallback(() => {
    let alive = true;
    fetchRecordOptions(access, publicationId ? { publication: publicationId } : { version: versionId ?? "" })
      .then((o) => {
        if (!alive) return;
        setOpts(o); setLoadErr(""); setNowMs(Date.now());
        const pubs = o.publications;
        const first = publicationId ? pubs.find((p) => p.id === publicationId) : pubs.find((p) => p.can_record) ?? pubs[0];
        if (first) {
          setPubId((x) => x || first.id);
          if (first.published) {
            setUrl((x) => x || first.published!.url);
            setAt((x) => x || toLocalInput(first.published!.at, o.timezone));
            setVideoId((x) => x || first.published!.media_version_id);
          }
        }
        setAt((x) => x || toLocalInput(new Date().toISOString(), o.timezone));
        if (!versionId) setVideoId((x) => x || o.videos.find((v) => v.eligible)?.version_id || "");
      })
      .catch((e: Error) => { if (alive) setLoadErr(e.message); });
    return () => { alive = false; };
  }, [access, publicationId, versionId]);
  useEffect(() => load(), [load, tick]);

  const tz = opts?.timezone ?? "Asia/Dubai";
  const pub: Publication | undefined = opts?.publications.find((p) => p.id === pubId);
  const correcting = pub?.status === "publicada";
  const urlProblem = pub ? postUrlProblem(pub.platform, url, pub.account_handle) : null;
  const parsed = pub && url.trim() ? parsePostUrl(pub.platform, url) : null;
  const atIso = at ? fromLocalInput(at, tz) : null;
  const future = !!atIso && nowMs > 0 && new Date(atIso).getTime() > nowMs + 5 * 60_000;
  const before = !!atIso && !!pub?.approved_at && new Date(atIso).getTime() < new Date(pub.approved_at).getTime() - 5 * 60_000;
  const eligibleVideos = useMemo(() => (opts?.videos ?? []).filter((v) => v.eligible), [opts]);
  const canSubmit = !!pub && !!parsed && !urlProblem && !!atIso && !future && !before && !!videoId && !busy
    && (pub.can_record ?? false) && (!correcting || reason.trim().length >= 3)
    && (!versionId || !!opts?.video?.approved);

  const submit = async () => {
    if (!pub || !atIso) return;
    setBusy(true); setErr("");
    try {
      const r = await recordPublished(access, pub.id, { url: url.trim(), published_at: atIso, media_version_id: videoId, revision: pub.revision },
        correcting ? reason.trim() : null);
      onDone(r.replayed ? "Já estava registado assim. Nada mudou."
        : r.corrected ? "Registo corrigido. A correção ficou no histórico com o motivo."
        : `Registado como publicado em @${r.account_handle}. As métricas deste post ficam ligadas a esta publicação.`);
      onClose();
    } catch (e) {
      const code = (e as { code?: string }).code;
      setErr(code === "40001" ? "A publicação mudou desde que a abriste. Fecha e abre outra vez." : (e as Error).message);
    } finally { setBusy(false); }
  };

  return (
    <Dialog open onOpenChange={(v) => { if (!v && !busy) onClose(); }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{correcting ? "Corrigir o registo da publicação" : "Registar publicação"}</DialogTitle>
          <DialogDescription>
            Para quando já publicaste à mão na app da plataforma. A app não publica nada: guarda o link do post, a hora e o vídeo aprovado, e liga as métricas a esta publicação.
          </DialogDescription>
        </DialogHeader>

        {loadErr ? (
          <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{loadErr}
            <Button size="sm" variant="outline" onClick={() => { setLoadErr(""); setTick((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
        ) : !opts ? (
          <div className="flex flex-col gap-2" aria-busy="true" aria-label="A carregar"><Skeleton className="h-9" /><Skeleton className="h-9" /><Skeleton className="h-9" /></div>
        ) : !opts.can_record ? (
          <Alert><AlertDescription>Não tens a capacidade de registar publicações neste cliente. Pede a quem gere as permissões.</AlertDescription></Alert>
        ) : versionId && opts.video && !opts.video.approved ? (
          <Alert><AlertDescription>Este vídeo ainda não está aprovado na revisão. Só se regista o que foi aprovado.</AlertDescription></Alert>
        ) : versionId && opts.video && !opts.video.current ? (
          <Alert><AlertDescription>Esta já não é a versão atual do vídeo. Abre a versão mais recente.</AlertDescription></Alert>
        ) : opts.publications.length === 0 ? (
          <Alert><AlertDescription>
            Ainda não há publicações aprovadas deste guião. Planeia a publicação (conta, dia e hora) e aprova-a no{" "}
            <WsLink href="/calendario?l=pub" className="underline underline-offset-2">calendário de publicações</WsLink>; depois regista aqui.
          </AlertDescription></Alert>
        ) : (
          <form className="flex flex-col gap-3 text-sm" onSubmit={(e) => { e.preventDefault(); if (canSubmit) void submit(); }}>
            {!publicationId && (
              <label className="flex flex-col gap-1">Publicação aprovada
                <select aria-label="Publicação aprovada" className={selectCls} value={pubId}
                  onChange={(e) => { setPubId(e.target.value); setReason(""); setErr(""); }}>
                  {opts.publications.map((p) => (
                    <option key={p.id} value={p.id}>
                      {dayTitle(p.local_day)} {p.local_time} · {PLATFORM_LABEL[p.platform]} @{p.account_handle}{p.status === "publicada" ? " · já registada" : ""}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {pub && (
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 rounded-md border p-2">
                <dt className="text-muted-foreground">Destino</dt><dd>@{pub.account_handle} · {PLATFORM_LABEL[pub.platform]}</dd>
                <dt className="text-muted-foreground">Guião</dt><dd>{pub.content_n} · versão {pub.version_no}{pub.variant ? ` · ${pub.variant.label}` : ""}</dd>
                <dt className="text-muted-foreground">Planeada</dt><dd>{dayTitle(pub.local_day)} às {pub.local_time} ({tz})</dd>
              </dl>
            )}
            {pub && pub.can_record === false && pub.record_blocked && pub.record_blocked !== "sem_capacidade" && (
              <Alert><AlertDescription>{RECORD_BLOCKED_LABEL[pub.record_blocked] ?? pub.record_blocked}</AlertDescription></Alert>
            )}

            {versionId && opts.video ? (
              <p>Vídeo: <b>{opts.video.title}</b> · v{opts.video.version} (aprovado)</p>
            ) : !opts.media_available ? (
              <Alert><AlertDescription>A biblioteca de media não está disponível para ti neste cliente: não dá para escolher o vídeo publicado.</AlertDescription></Alert>
            ) : (
              <label className="flex flex-col gap-1">Vídeo publicado (versão aprovada)
                <select aria-label="Vídeo publicado" className={selectCls} value={videoId} onChange={(e) => setVideoId(e.target.value)}>
                  <option value="">{eligibleVideos.length ? "Escolhe o vídeo" : "Sem vídeos aprovados deste guião"}</option>
                  {opts.videos.map((v) => (
                    <option key={v.version_id} value={v.version_id} disabled={!v.eligible}>
                      {variantName(v.variant)}{v.style ? ` · ${v.style}` : ""} · {v.title} · v{v.version}{v.eligible ? "" : " (por aprovar na revisão)"}
                    </option>
                  ))}
                </select>
                {eligibleVideos.length === 0 && (
                  <span className="text-xs text-muted-foreground">Aprova o vídeo na <WsLink href="/revisao?ver=videos" className="underline underline-offset-2">revisão</WsLink> primeiro.</span>
                )}
              </label>
            )}

            <label className="flex flex-col gap-1">Link do post
              <Input aria-label="Link do post" inputMode="url" autoComplete="off" value={url} maxLength={1000} aria-invalid={!!urlProblem}
                placeholder={pub ? POST_URL_HINT[pub.platform] : "https://"} onChange={(e) => setUrl(e.target.value)} />
              {urlProblem ? <span role="alert" className="text-xs text-destructive">{urlProblem}</span>
                : parsed && (
                  <a href={parsed.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs underline underline-offset-2">
                    <ExternalLinkIcon className="size-3" /> Confirmar que abre o post certo
                  </a>
                )}
            </label>
            <label className="flex flex-col gap-1">Publicado em ({tz})
              <Input aria-label="Publicado em" type="datetime-local" value={at} aria-invalid={future || before} onChange={(e) => setAt(e.target.value)} />
              {future && <span role="alert" className="text-xs text-destructive">A hora não pode ser no futuro.</span>}
              {before && <span role="alert" className="text-xs text-destructive">É anterior à aprovação. Só se regista o que saiu depois de aprovado.</span>}
            </label>
            {correcting && (
              <label className="flex flex-col gap-1">Motivo da correção
                <Textarea aria-label="Motivo da correção" rows={2} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)}
                  placeholder="Ex.: colei o link do post errado." />
                <span className="text-xs text-muted-foreground">Fica no histórico com o registo anterior.</span>
              </label>
            )}
            {err && <p role="alert" className="text-destructive">{err}</p>}
            <DialogFooter>
              <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>Cancelar</Button>
              <Button type="submit" disabled={!canSubmit}>{busy && <Loader2Icon className="animate-spin" />} {correcting ? "Corrigir registo" : "Confirmar que foi publicado"}</Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
