"use client";

import { useEffect, useRef, useState } from "react";
import { ArchiveRestoreIcon, CopyIcon, DownloadIcon, ExternalLinkIcon, Loader2Icon, ReplaceIcon, RotateCwIcon, Share2Icon, Trash2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useLoad } from "@/components/perf/perf-shared";
import { ConfirmDialog, KindIcon, fmtDateTime, selectCls } from "@/components/media/media-shared";
import type { Access } from "@/lib/access";
import {
  addLink, createShare, errCode, fetchAsset, purge, restoreAsset, revokeShare, saveAsset, shareUrl, signedUrl, trashAsset,
  type MediaAssetDetail, type MediaLibrary, type MediaVersion,
} from "@/lib/media";
import { FORMATS, KIND_LABEL, STATUS_LABEL, VERSION_STATE_LABEL, bytes, kindAccepts, mimeOf, precheck, previewKind, splitTags, type MediaStatus } from "@/lib/media-format";

export function MediaAssetSheet({ access, lib, id, onClose, onChanged, onReplace }: {
  access: Access; lib: MediaLibrary; id: string; onClose: () => void; onChanged: () => void; onReplace: (assetId: string, f: File) => void;
}) {
  const r = useLoad(() => fetchAsset(access, id), `${access.ws}:${id}`);
  const [n, setN] = useState(0);
  const reload = () => { r.reload(); onChanged(); setN((x) => x + 1); };
  const a = r.data;
  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">{a && <KindIcon kind={a.kind} />}{a?.title ?? "Ativo"}</SheetTitle>
          <SheetDescription>{a ? `${KIND_LABEL[a.kind]} · ${a.versions} versão(ões) · criado por ${a.created_label ?? "?"} em ${fmtDateTime(a.created_at, lib.timezone)}` : "A carregar"}</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-4 pb-6 text-sm">
          {r.error ? (
            <Alert variant={errCode(r.error) === "42501" || errCode(r.error) === "P0002" ? "default" : "destructive"}>
              <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
                <span>{errCode(r.error) === "P0002" ? "Este ativo não existe neste cliente ou não tens acesso." : (r.error as Error).message}</span>
                <Button size="sm" variant="outline" onClick={r.reload}><RotateCwIcon /> Tentar de novo</Button>
              </AlertDescription>
            </Alert>
          ) : !a ? <Skeleton className="h-64 w-full" /> : (
            <>
              <Preview key={`${a.current?.id}-${n}`} access={access} lib={lib} a={a} />
              <Actions access={access} lib={lib} a={a} onChanged={reload} onReplace={onReplace} onClose={onClose} />
              {a.lifecycle === "ativo" && <MetaForm key={a.lock_version} access={access} lib={lib} a={a} onSaved={reload} />}
              <History access={access} lib={lib} a={a} />
              {a.shares && a.lifecycle === "ativo" && <Shares access={access} lib={lib} a={a} onChanged={reload} />}
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

function Preview({ access, lib, a }: { access: Access; lib: MediaLibrary; a: MediaAssetDetail }) {
  const v = a.current;
  const kind = v?.source === "upload" ? previewKind(v.mime) : null;
  const [url, setUrl] = useState<{ url: string; expires_at: string } | null>(null);
  const [err, setErr] = useState("");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (!v || !kind) return;
    let alive = true;
    signedUrl(access, v.id, "preview").then((u) => { if (alive) { setUrl(u); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, v, kind, attempt]);
  if (!v) return <p className="rounded-lg border border-dashed p-4 text-muted-foreground">Ainda sem versão pronta.</p>;
  if (v.source === "link") {
    return (
      <div className="flex flex-col gap-1 rounded-lg border p-3">
        <span className="text-xs text-muted-foreground">Link externo (não é guardado na app)</span>
        <a className="inline-flex items-center gap-1 break-all text-primary underline-offset-4 hover:underline" href={v.external_url ?? undefined} target="_blank" rel="noopener noreferrer">
          <ExternalLinkIcon className="size-4 shrink-0" aria-hidden /> {v.external_url}
        </a>
      </div>
    );
  }
  if (!kind) return <p className="rounded-lg border border-dashed p-4 text-muted-foreground">Sem pré-visualização para {v.mime}. Descarrega para abrir.</p>;
  if (err) {
    return (
      <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">
        <span>Não consegui pré-visualizar: {err}</span>
        <Button size="sm" variant="outline" onClick={() => setAttempt((x) => x + 1)}><RotateCwIcon /> Tentar de novo</Button>
      </AlertDescription></Alert>
    );
  }
  if (!url) return <Skeleton className="aspect-video w-full" aria-label="A preparar a pré-visualização" />;
  const onFail = () => setErr("o link expirou ou o ficheiro não abriu");
  return (
    <figure className="flex flex-col gap-1" data-preview={kind}>
      {/* URL assinado de 5 min: next/image não serve (não otimiza nem guarda em cache um link temporário privado) */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {kind === "image" && <img src={url.url} alt={a.title} className="max-h-96 w-full rounded-lg object-contain" onError={onFail} />}
      {kind === "video" && <video src={url.url} controls className="max-h-96 w-full rounded-lg bg-black" onError={onFail} />}
      {kind === "audio" && <audio src={url.url} controls className="w-full" onError={onFail} />}
      {kind === "pdf" && <iframe src={url.url} title={a.title} className="h-96 w-full rounded-lg border" />}
      <figcaption className="text-xs text-muted-foreground">Link temporário, válido até {fmtDateTime(url.expires_at, lib.timezone)}.
        {" "}<button type="button" className="underline" onClick={() => setAttempt((x) => x + 1)}>Renovar</button></figcaption>
    </figure>
  );
}

async function download(access: Access, v: MediaVersion) {
  const u = await signedUrl(access, v.id, "download");
  const el = document.createElement("a");
  el.href = u.url; el.rel = "noopener"; el.download = u.filename;
  document.body.appendChild(el); el.click(); el.remove();
}

function Actions({ access, lib, a, onChanged, onReplace, onClose }: {
  access: Access; lib: MediaLibrary; a: MediaAssetDetail; onChanged: () => void; onReplace: (assetId: string, f: File) => void; onClose: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState("");
  const [trash, setTrash] = useState(false);
  const [reason, setReason] = useState("");
  const [purgeOpen, setPurgeOpen] = useState(false);
  const [newLink, setNewLink] = useState("");
  const act = async (k: string, f: () => Promise<unknown>) => { setBusy(k); setErr(""); try { await f(); } catch (e) { setErr((e as Error).message); } finally { setBusy(""); } };
  const v = a.current;
  return (
    <section className="flex flex-col gap-2" aria-label="Ações">
      <div className="flex flex-wrap gap-2">
        {v?.source === "upload" && lib.can.download && (
          <Button size="sm" variant="outline" disabled={!!busy} onClick={() => void act("dl", () => download(access, v))}>
            {busy === "dl" ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Descarregar
          </Button>
        )}
        {a.lifecycle === "ativo" && lib.can.upload && a.kind !== "link_externo" && (
          <>
            <input ref={fileRef} type="file" className="hidden" tabIndex={-1} aria-hidden onChange={(e) => {
              const f = e.target.files?.[0]; e.target.value = "";
              if (!f) return;
              const why = precheck(f, lib.policy, lib.usage) ?? (kindAccepts(a.kind, mimeOf(f.name, f.type)) ? null : `Este ficheiro não serve para ${KIND_LABEL[a.kind].toLowerCase()}.`);
              if (why) { setErr(why); return; }
              onReplace(a.id, f); onClose();
            }} />
            <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()}><ReplaceIcon /> Substituir (versão nova)</Button>
          </>
        )}
        {a.lifecycle === "ativo" && lib.can.upload && <Button size="sm" variant="ghost" onClick={() => setTrash(true)}><Trash2Icon /> Mandar para o lixo</Button>}
        {a.lifecycle === "no_lixo" && lib.can.upload && (
          <Button size="sm" variant="outline" disabled={!!busy} onClick={() => void act("restore", async () => { await restoreAsset(access, a.id); onChanged(); })}>
            {busy === "restore" ? <Loader2Icon className="animate-spin" /> : <ArchiveRestoreIcon />} Recuperar
          </Button>
        )}
        {a.lifecycle === "no_lixo" && lib.can.manage && <Button size="sm" variant="destructive" onClick={() => setPurgeOpen(true)}><Trash2Icon /> Apagar definitivamente</Button>}
      </div>
      {a.lifecycle === "no_lixo" && (
        <p className="text-xs text-muted-foreground">No lixo desde {fmtDateTime(a.trashed_at, lib.timezone)} por {a.trashed_label ?? "?"}{a.trash_reason ? ` (${a.trash_reason})` : ""}. Recuperável até {fmtDateTime(a.purge_after, lib.timezone)}. A eliminação automática no fim do prazo ainda não existe: só se apaga por quem gere a biblioteca, com confirmação.</p>
      )}
      {a.lifecycle === "eliminado" && <p className="text-xs text-muted-foreground">Apagado definitivamente. Fica só o histórico.</p>}
      {a.kind === "link_externo" && a.lifecycle === "ativo" && lib.can.upload && (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex min-w-0 flex-1 flex-col gap-1">Trocar o link (versão nova)
            <Input value={newLink} onChange={(e) => setNewLink(e.target.value)} placeholder="https://..." inputMode="url" />
          </label>
          <Button size="sm" disabled={!!busy || !/^https:\/\/\S+\.\S+/.test(newLink.trim())}
            onClick={() => void act("link", async () => { await addLink(access, a.id, { url: newLink.trim() }); setNewLink(""); onChanged(); })}>
            {busy === "link" && <Loader2Icon className="animate-spin" />} Guardar link
          </Button>
        </div>
      )}
      {err && <p role="alert" className="text-destructive">{err}</p>}
      <ConfirmDialog open={trash} title="Mandar para o lixo" confirmLabel="Mandar para o lixo"
        description={`Fica recuperável durante ${lib.policy.trash_days} dias. Os links de partilha deste ativo deixam de funcionar.`}
        onCancel={() => setTrash(false)}
        onConfirm={async () => { await trashAsset(access, a.id, reason); setTrash(false); setReason(""); onChanged(); }}>
        <label className="flex flex-col gap-1 text-sm">Motivo (opcional)<Input value={reason} onChange={(e) => setReason(e.target.value)} /></label>
      </ConfirmDialog>
      <ConfirmDialog open={purgeOpen} typed title="Apagar definitivamente" confirmLabel="Apagar definitivamente"
        description="Apaga os ficheiros de todas as versões do armazenamento. Fica só o histórico. Não há volta atrás."
        onCancel={() => setPurgeOpen(false)}
        onConfirm={async (typed) => {
          const r = await purge(access, "lixo", [a.id], typed);
          if (r.assets_purged === 0) throw new Error(`Ainda há ${r.remaining.length} ficheiro(s) no armazenamento${r.storage_error ? `: ${r.storage_error}` : ""}. Tenta de novo.`);
          setPurgeOpen(false); onChanged();
        }} />
    </section>
  );
}

function MetaForm({ access, lib, a, onSaved }: { access: Access; lib: MediaLibrary; a: MediaAssetDetail; onSaved: () => void }) {
  const [title, setTitle] = useState(a.title);
  const [tags, setTags] = useState(a.tags.join(" "));
  const [project, setProject] = useState(a.project?.id ?? "");
  const [format, setFormat] = useState(a.format ?? "");
  const [status, setStatus] = useState<MediaStatus>(a.status);
  const [content, setContent] = useState(a.content?.id ?? "");
  const [take, setTake] = useState(a.take_id ?? "");
  const [pub, setPub] = useState(a.publication_id ?? "");
  const [notes, setNotes] = useState(a.notes ?? "");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad: boolean } | null>(null);
  const contentChanged = content !== (a.content?.id ?? "");
  const ro = !lib.can.upload;
  const save = async () => {
    setBusy(true); setMsg(null);
    try {
      await saveAsset(access, a.id, {
        title: title.trim(), tags: splitTags(tags), project_id: project || null, format: format || null, status,
        content_id: content || null, take_id: contentChanged ? null : take || null, publication_id: contentChanged ? null : pub || null, notes: notes.trim() || null,
      }, a.lock_version);
      setMsg({ text: contentChanged ? "Guardado. Escolhe agora o take e a publicação do guião novo, se quiseres." : "Guardado.", bad: false });
      onSaved();
    } catch (e) {
      setMsg({ text: errCode(e) === "PT409" ? "Alguém mudou este ativo entretanto. Recarreguei: revê e volta a guardar." : (e as Error).message, bad: true });
      if (errCode(e) === "PT409") onSaved();
    } finally { setBusy(false); }
  };
  return (
    <section className="flex flex-col gap-3" aria-labelledby="media-meta">
      <h3 id="media-meta" className="font-semibold">Dados e ligações</h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="flex flex-col gap-1 sm:col-span-2">Título<Input value={title} disabled={ro} onChange={(e) => setTitle(e.target.value)} /></label>
        <label className="flex flex-col gap-1">Estado
          <select className={selectCls} value={status} disabled={ro} onChange={(e) => setStatus(e.target.value as MediaStatus)}>
            {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Formato
          <select className={selectCls} value={format} disabled={ro} onChange={(e) => setFormat(e.target.value)}>
            <option value="">Sem formato</option>{FORMATS.map((f) => <option key={f} value={f}>{f}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Campanha
          <select className={selectCls} value={project} disabled={ro} onChange={(e) => setProject(e.target.value)}>
            <option value="">Sem campanha</option>{lib.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Etiquetas<Input value={tags} disabled={ro} onChange={(e) => setTags(e.target.value)} placeholder="final dubai" /></label>
        <label className="flex flex-col gap-1 sm:col-span-2">Guião
          <select className={selectCls} value={content} disabled={ro} onChange={(e) => setContent(e.target.value)}>
            <option value="">Sem guião</option>{a.options.contents.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Take
          <select className={selectCls} value={contentChanged ? "" : take} disabled={ro || contentChanged || a.options.takes.length === 0} onChange={(e) => setTake(e.target.value)}>
            <option value="">{a.options.takes.length ? "Sem take" : "Sem takes neste guião"}</option>{a.options.takes.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Publicação
          <select className={selectCls} value={contentChanged ? "" : pub} disabled={ro || contentChanged || a.options.publications.length === 0} onChange={(e) => setPub(e.target.value)}>
            <option value="">{a.options.publications.length ? "Sem publicação" : "Sem publicações planeadas"}</option>{a.options.publications.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 sm:col-span-2">Notas<Textarea value={notes} disabled={ro} onChange={(e) => setNotes(e.target.value)} rows={2} /></label>
      </div>
      {!ro && <Button className="self-start" size="sm" disabled={busy || !title.trim()} onClick={() => void save()}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button>}
      {msg && <p role={msg.bad ? "alert" : "status"} className={msg.bad ? "text-destructive" : ""}>{msg.text}</p>}
    </section>
  );
}

function History({ access, lib, a }: { access: Access; lib: MediaLibrary; a: MediaAssetDetail }) {
  const [err, setErr] = useState("");
  return (
    <section className="flex flex-col gap-2" aria-labelledby="media-history">
      <h3 id="media-history" className="font-semibold">Versões</h3>
      <ol className="flex flex-col divide-y rounded-lg border">
        {a.history.map((v) => (
          <li key={v.id} className="flex flex-wrap items-center justify-between gap-2 p-3" data-version={v.version_no}>
            <span className="flex min-w-0 flex-col">
              <span className="flex flex-wrap items-center gap-2">
                <b>v{v.version_no}</b>
                <Badge variant={v.state === "pronta" ? "secondary" : "outline"}>{VERSION_STATE_LABEL[v.state] ?? v.state}</Badge>
                {a.current?.id === v.id && <Badge>atual</Badge>}
              </span>
              <span className="truncate text-xs text-muted-foreground">
                {v.source === "link" ? v.external_url : `${v.original_name} · ${bytes(v.size_bytes)} · ${v.mime}`}
              </span>
              <span className="text-xs text-muted-foreground">
                {v.uploaded_label ?? "?"} · {fmtDateTime(v.created_at, lib.timezone)}
                {v.source === "upload" && v.state === "pronta" ? ` · SHA-256 ${v.checksum_verified ? "conferido" : "declarado"} ${v.sha256?.slice(0, 12)}…` : ""}
                {v.failed_reason ? ` · ${v.failed_reason}` : ""}
              </span>
            </span>
            {v.source === "upload" && v.state === "pronta" && lib.can.download && a.lifecycle !== "eliminado" && (
              <Button size="xs" variant="ghost" aria-label={`Descarregar versão ${v.version_no}`} onClick={() => download(access, v).catch((e: Error) => setErr(e.message))}><DownloadIcon /></Button>
            )}
          </li>
        ))}
      </ol>
      {err && <p role="alert" className="text-destructive">{err}</p>}
    </section>
  );
}

function Shares({ access, lib, a, onChanged }: { access: Access; lib: MediaLibrary; a: MediaAssetDetail; onChanged: () => void }) {
  const [hours, setHours] = useState(24);
  const [note, setNote] = useState("");
  const [created, setCreated] = useState<{ url: string; expires_at: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [copied, setCopied] = useState(false);
  const v = a.current;
  const canShare = v?.source === "upload" && v.state === "pronta";
  return (
    <section className="flex flex-col gap-2" aria-labelledby="media-shares">
      <h3 id="media-shares" className="font-semibold">Links de partilha</h3>
      <p className="text-xs text-muted-foreground">Para quem não tem conta. O link abre a versão atual (v{v?.version_no ?? "-"}) e expira sozinho; podes revogá-lo antes. Cada abertura fica no histórico.</p>
      {canShare ? (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1">Validade
            <select className={selectCls} value={hours} onChange={(e) => setHours(Number(e.target.value))}>
              <option value={1}>1 hora</option><option value={24}>24 horas</option><option value={72}>3 dias</option><option value={168}>7 dias</option>
            </select>
          </label>
          <label className="flex min-w-0 flex-1 flex-col gap-1">Nota (para quem é)<Input value={note} onChange={(e) => setNote(e.target.value)} /></label>
          <Button size="sm" disabled={busy} onClick={async () => {
            setBusy(true); setErr(""); setCopied(false);
            try { const s = await createShare(access, v!.id, hours, note); setCreated({ url: shareUrl(s.token), expires_at: s.expires_at }); setNote(""); onChanged(); }
            catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
          }}>{busy ? <Loader2Icon className="animate-spin" /> : <Share2Icon />} Criar link</Button>
        </div>
      ) : <p className="text-xs text-muted-foreground">Só uma versão pronta carregada (não um link externo) se partilha.</p>}
      {created && (
        <div className="flex flex-col gap-1 rounded-lg border p-3" role="status">
          <span className="text-xs text-muted-foreground">Copia agora: este link não volta a aparecer. Válido até {fmtDateTime(created.expires_at, lib.timezone)}.</span>
          <div className="flex items-center gap-2">
            <Input readOnly value={created.url} aria-label="Link de partilha" onFocus={(e) => e.target.select()} />
            <Button size="sm" variant="outline" onClick={async () => {
              try { await navigator.clipboard.writeText(created.url); setCopied(true); } catch { setErr("Não consegui copiar: seleciona o link e copia à mão."); }
            }}><CopyIcon /> {copied ? "Copiado" : "Copiar"}</Button>
          </div>
        </div>
      )}
      {err && <p role="alert" className="text-destructive">{err}</p>}
      {a.shares && a.shares.length > 0 && (
        <ul className="flex flex-col divide-y rounded-lg border">
          {a.shares.map((s) => (
            <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 p-3" data-share={s.id}>
              <span className="flex min-w-0 flex-col text-xs">
                <span>v{s.version_no} · {s.note ?? "sem nota"} · {s.active ? `válido até ${fmtDateTime(s.expires_at, lib.timezone)}` : s.revoked_at ? "revogado" : "expirado"}</span>
                <span className="text-muted-foreground">{s.created_label ?? "?"} · aberto {s.open_count} vez(es){s.last_opened_at ? `, última ${fmtDateTime(s.last_opened_at, lib.timezone)}` : ""}</span>
              </span>
              {s.active && <Button size="xs" variant="ghost" onClick={async () => { try { await revokeShare(access, s.id); onChanged(); } catch (e) { setErr((e as Error).message); } }}>Revogar</Button>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
