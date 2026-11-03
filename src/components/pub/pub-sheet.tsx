"use client";

import { useEffect, useMemo, useState } from "react";
import { Loader2Icon, RotateCwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import type { Access } from "@/lib/access";
import { dayTitle } from "@/lib/calendar";
import {
  approvePublication, archiveVariant, cancelPublication, fetchContentDetail, fetchContentOptions, savePublication, saveVariant,
  type ContentDetail, type ContentOption, type Publication, type PubCalendar, type PubInput,
} from "@/lib/pub";
import {
  BLOCKED_LABEL, cleanElements, CONNECTION_LABEL, ELEMENT_HINT, ELEMENT_KEYS, ELEMENT_LABEL, parseHashtags, PLATFORM_LABEL, PLATFORMS,
  SIDE_LABEL, STATUS_LABEL, variantDiff, type Elements, type Platform,
} from "@/lib/pub-rules";
import { fromLocalInput, toLocalInput } from "@/lib/tasks";
import { cn } from "@/lib/utils";

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm";
const when = (iso: string, tz: string) => new Date(iso).toLocaleString("pt-PT", { timeZone: tz, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

type Props = { access: Access; data: PubCalendar; pub: Publication | null; defaultDay: string; onClose: () => void; onChanged: (msg?: string) => void };

/** Planear, mudar, aprovar e cancelar uma publicação. A aprovação fica presa à revisão que se vê aqui. */
export function PubSheet({ access, data, pub, defaultDay, onClose, onChanged }: Props) {
  const tz = data.timezone;
  const isNew = !pub;
  const editable = data.can.schedule && pub?.status !== "cancelada";
  const [options, setOptions] = useState<ContentOption[] | null>(null);
  const [contentId, setContentId] = useState(pub?.content_id ?? "");
  const [detail, setDetail] = useState<ContentDetail | null>(null);
  const [detailErr, setDetailErr] = useState("");
  const [detailTick, setDetailTick] = useState(0);
  const [versionId, setVersionId] = useState(pub?.content_version_id ?? "");
  const [variantId, setVariantId] = useState(pub?.variant?.id ?? "");
  const [accountId, setAccountId] = useState(pub?.account_id ?? data.accounts.find((a) => a.active)?.id ?? "");
  const [at, setAt] = useState(pub ? toLocalInput(pub.scheduled_at, tz) : `${defaultDay}T18:00`);
  const [caption, setCaption] = useState(pub?.caption ?? "");
  const [tags, setTags] = useState((pub?.hashtags ?? []).join(" "));
  const [kind, setKind] = useState<"original" | "republicacao">(pub?.kind ?? "original");
  const [parentId, setParentId] = useState(pub?.parent_publication_id ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [cancelReason, setCancelReason] = useState("");
  const [confirmApprove, setConfirmApprove] = useState(false);
  const [variantForm, setVariantForm] = useState(false);

  useEffect(() => {
    if (!isNew) return;
    let alive = true;
    fetchContentOptions(access).then((o) => { if (alive) setOptions(o); }).catch((e: Error) => { if (alive) setDetailErr(e.message); });
    return () => { alive = false; };
  }, [access, isNew]);
  useEffect(() => {
    if (!contentId || !editable) return;
    let alive = true;
    fetchContentDetail(access, contentId)
      .then((d) => { if (!alive) return; setDetail(d); setDetailErr(""); setVersionId((v) => v || d.approved_version_id || d.versions[0]?.id || ""); })
      .catch((e: Error) => { if (alive) setDetailErr(e.message); });
    return () => { alive = false; };
  }, [access, contentId, editable, detailTick]);

  const variants = useMemo(() => (detail?.variants ?? []).filter((v) => v.content_version_id === versionId && (!v.archived || v.id === pub?.variant?.id)), [detail, versionId, pub]);
  const parents = data.publications.filter((p) => p.content_id === contentId && p.status !== "cancelada" && p.id !== pub?.id && p.kind === "original");
  const parsedTags = parseHashtags(tags);
  const account = data.accounts.find((a) => a.id === accountId);

  const input = (): PubInput => {
    const i: PubInput = {
      content_version_id: versionId, variant_id: variantId || null, account_id: accountId,
      scheduled_at: fromLocalInput(at, tz) ?? undefined, caption, hashtags: parsedTags.tags,
    };
    if (isNew) { i.content_id = contentId; i.kind = kind; if (kind === "republicacao") i.parent_publication_id = parentId; }
    return i;
  };
  const save = async () => {
    setBusy(true); setErr("");
    try {
      const r = await savePublication(access, pub?.id ?? null, input(), pub?.lock_version);
      onChanged(isNew ? `Publicação planeada para ${dayTitle(r.local_day)} às ${r.local_time} em @${r.account_handle}.`
        : pub?.status === "aprovada" && r.status === "planeada" ? "Guardado. A aprovação anterior deixou de valer: precisa de nova aprovação." : "Guardado.");
      onClose();
    } catch (e) {
      const code = (e as { code?: string }).code;
      setErr(code === "PT409" ? "Alguém mudou esta publicação entretanto. Fecha e abre outra vez." : (e as Error).message);
    } finally { setBusy(false); }
  };
  const approve = async () => {
    if (!pub) return;
    setBusy(true); setErr(""); setConfirmApprove(false);
    try {
      const r = await approvePublication(access, pub.id, pub.revision);
      onChanged(r.status === "aprovada" ? "Aprovada. Fica pronta para o publicador quando as plataformas aprovarem a app." : "A tua aprovação ficou registada. Falta a outra parte.");
      onClose();
    } catch (e) {
      const code = (e as { code?: string }).code;
      setErr(code === "40001" ? "A publicação mudou desde que a abriste. Fecha e abre outra vez para veres a versão nova." : (e as Error).message);
    } finally { setBusy(false); }
  };
  const cancel = async () => {
    if (!pub) return;
    setBusy(true); setErr("");
    try { await cancelPublication(access, pub.id, cancelReason.trim()); onChanged("Publicação cancelada."); onClose(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  const canSave = editable && !!contentId && !!versionId && !!accountId && !!at && parsedTags.invalid.length === 0 && (kind === "original" || !!parentId) && !busy;

  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>{isNew ? "Planear publicação" : `Guião ${pub.content_n} · @${pub.account_handle}`}</SheetTitle>
          <SheetDescription>
            {isNew ? "Escolhe a versão, a variante e o destino. Fica por aprovar até alguém com a capacidade aprovar."
              : `${PLATFORM_LABEL[pub.platform]} · ${dayTitle(pub.local_day)} às ${pub.local_time} · revisão ${pub.revision}`}
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6 text-sm">
          {pub && (
            <div className="flex flex-wrap gap-2">
              <Badge variant={pub.status === "aprovada" ? "default" : "outline"}>{STATUS_LABEL[pub.status]}</Badge>
              {pub.kind === "republicacao" && <Badge variant="secondary">Republicação</Badge>}
              <Badge variant="outline">Versão {pub.version_no}{pub.version_approved ? " (aprovada)" : " (por aprovar)"}</Badge>
              {pub.variant && <Badge variant="outline">{pub.variant.label}{pub.variant.counts_as_new ? "" : " · não conta como nova"}</Badge>}
              {pub.cancelled_reason && <span className="text-muted-foreground">Motivo: {pub.cancelled_reason}</span>}
            </div>
          )}

          {pub && pub.conflicts.length > 0 && (
            <ul className="flex flex-col gap-1" aria-label="Conflitos e avisos">
              {pub.conflicts.map((c) => (
                <li key={c.code} className={cn("rounded border px-2 py-1", c.severity === "bloqueia" ? "border-destructive text-destructive" : "border-amber-500/60")}>
                  <b>{c.severity === "bloqueia" ? "Bloqueia" : "Aviso"}:</b> {c.message}
                </li>
              ))}
            </ul>
          )}

          {detailErr && (
            <p role="alert" className="flex flex-wrap items-center gap-2 text-destructive">{detailErr}
              <Button size="sm" variant="outline" onClick={() => setDetailTick((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></p>
          )}

          {editable ? (
            <form className="flex flex-col gap-3" onSubmit={(e) => { e.preventDefault(); if (canSave) save(); }}>
              {isNew && (
                <label className="flex flex-col gap-1">Guião
                  <select aria-label="Guião" className={selectCls} value={contentId} disabled={!options} onChange={(e) => { setContentId(e.target.value); setVersionId(""); setVariantId(""); setDetail(null); }}>
                    <option value="">{options ? (options.length ? "Escolhe o guião" : "Sem guiões disponíveis") : "A carregar..."}</option>
                    {options?.map((o) => <option key={o.id} value={o.id}>{dayTitle(o.date)} · {o.n} · {o.hook || o.tema || "Sem hook"}{o.approved ? "" : " (por aprovar)"}</option>)}
                  </select>
                </label>
              )}
              {contentId && (
                <>
                  <label className="flex flex-col gap-1">Versão do guião
                    <select aria-label="Versão do guião" className={selectCls} value={versionId} disabled={!detail} onChange={(e) => { setVersionId(e.target.value); setVariantId(""); }}>
                      {!detail && <option value={versionId}>A carregar...</option>}
                      {detail?.versions.map((v) => <option key={v.id} value={v.id}>Versão {v.version_no}{v.approved ? " · aprovada" : ""}{v.current ? " · atual" : ""}</option>)}
                    </select>
                    {detail && versionId && versionId !== detail.approved_version_id && <span className="text-xs text-amber-600 dark:text-amber-400">Só se aprova a publicação com a versão aprovada do guião.</span>}
                  </label>
                  <div className="flex flex-col gap-1">
                    <label className="flex flex-col gap-1">Variante
                      <select aria-label="Variante" className={selectCls} value={variantId} disabled={!detail} onChange={(e) => setVariantId(e.target.value)}>
                        <option value="">Original (sem variante)</option>
                        {variants.map((v) => <option key={v.id} value={v.id}>{v.label}{v.platform ? ` · ${PLATFORM_LABEL[v.platform]}` : ""}{v.counts_as_new ? "" : " · não conta como nova"}</option>)}
                      </select>
                    </label>
                    {detail && !variantForm && <Button type="button" size="sm" variant="ghost" className="self-start" onClick={() => setVariantForm(true)}>Nova variante</Button>}
                  </div>
                </>
              )}
              <label className="flex flex-col gap-1">Conta
                <select aria-label="Conta" className={selectCls} value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                  <option value="">Escolhe a conta</option>
                  {data.accounts.filter((a) => a.active || a.id === accountId).map((a) => (
                    <option key={a.id} value={a.id}>@{a.handle} · {PLATFORM_LABEL[a.platform] ?? a.platform} · {CONNECTION_LABEL[a.connection_state] ?? a.connection_state}</option>
                  ))}
                </select>
                {account && account.connection_state !== "ligada" && <span className="text-xs text-muted-foreground">Conta por ligar: a publicação automática chega quando as plataformas aprovarem a app.</span>}
              </label>
              <label className="flex flex-col gap-1">Dia e hora ({tz})
                <Input aria-label="Dia e hora" type="datetime-local" value={at} min={`${data.today}T00:00`} onChange={(e) => setAt(e.target.value)} />
              </label>
              <label className="flex flex-col gap-1">Legenda
                <Textarea aria-label="Legenda" rows={4} maxLength={2200} value={caption} onChange={(e) => setCaption(e.target.value)} />
                <span className="text-xs text-muted-foreground">{caption.length}/2200</span>
              </label>
              <label className="flex flex-col gap-1">Hashtags
                <Input aria-label="Hashtags" value={tags} onChange={(e) => setTags(e.target.value)} placeholder="#dinheiro #dubai" />
                {parsedTags.invalid.length > 0 && <span role="alert" className="text-xs text-destructive">Inválidas: {parsedTags.invalid.join(" ")}</span>}
              </label>
              {isNew && (
                <div className="flex flex-col gap-2">
                  <label className="flex flex-col gap-1">Tipo
                    <select aria-label="Tipo" className={selectCls} value={kind} onChange={(e) => setKind(e.target.value as "original" | "republicacao")}>
                      <option value="original">Original</option>
                      <option value="republicacao">Republicação</option>
                    </select>
                  </label>
                  {kind === "republicacao" && (
                    <label className="flex flex-col gap-1">Publicação original
                      <select aria-label="Publicação original" className={selectCls} value={parentId} onChange={(e) => setParentId(e.target.value)}>
                        <option value="">{parents.length ? "Escolhe a original" : "Sem originais deste guião no período à vista"}</option>
                        {parents.map((p) => <option key={p.id} value={p.id}>{dayTitle(p.local_day)} {p.local_time} · @{p.account_handle}</option>)}
                      </select>
                      <span className="text-xs text-muted-foreground">Republicações precisam da capacidade própria de aprovação.</span>
                    </label>
                  )}
                </div>
              )}
              {pub?.status === "aprovada" && <p className="text-xs text-amber-600 dark:text-amber-400">Está aprovada. Mudar a versão, a variante, a conta, a hora, a legenda ou as hashtags retira a aprovação.</p>}
              {err && <p role="alert" className="text-destructive">{err}</p>}
              <Button type="submit" disabled={!canSave}>{busy && <Loader2Icon className="animate-spin" />} {isNew ? "Planear" : "Guardar"}</Button>
            </form>
          ) : pub && (
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
              <dt className="text-muted-foreground">Conta</dt><dd>@{pub.account_handle} · {PLATFORM_LABEL[pub.platform]}</dd>
              <dt className="text-muted-foreground">Legenda</dt><dd className="whitespace-pre-wrap">{pub.caption || "Sem legenda"}</dd>
              <dt className="text-muted-foreground">Hashtags</dt><dd>{pub.hashtags.join(" ") || "Sem hashtags"}</dd>
            </dl>
          )}

          {variantForm && detail && contentId && versionId && (
            <VariantForm access={access} contentId={contentId} versionId={versionId} detail={detail}
              onCancel={() => setVariantForm(false)} onSaved={(d, label) => {
                setDetail(d); setVariantForm(false);
                const v = d.variants.find((x) => x.label === label && x.content_version_id === versionId && !x.archived);
                if (v) setVariantId(v.id);
              }} onArchived={(d) => { setDetail(d); }} />
          )}

          {pub && (
            <section className="flex flex-col gap-2" aria-labelledby="pub-approvals-title">
              <h3 id="pub-approvals-title" className="font-semibold">Aprovação</h3>
              {pub.status === "planeada" && pub.missing.length > 0 && (
                <p>Falta: {pub.missing.map((m) => SIDE_LABEL[m] ?? m).join(" e ")}.</p>
              )}
              {pub.approvals.length === 0 ? <p className="text-muted-foreground">Ainda ninguém aprovou.</p> : (
                <ul className="flex flex-col gap-1">
                  {pub.approvals.map((a, i) => (
                    <li key={i} className={cn(a.invalidated_at && "text-muted-foreground line-through")}>
                      {a.actor_label ?? "?"} ({SIDE_LABEL[a.side]}, {a.actor_role}) aprovou a revisão {a.revision} em {when(a.decided_at, tz)}
                      {a.invalidated_reason && <span className="no-underline"> · {a.invalidated_reason}</span>}
                    </li>
                  ))}
                </ul>
              )}
              {pub.status === "planeada" && (pub.can_approve ? (
                <Button disabled={busy} onClick={() => setConfirmApprove(true)}>Aprovar esta versão e destino</Button>
              ) : pub.approve_blocked && pub.approve_blocked !== "sem_capacidade" && (
                <p className="text-muted-foreground">{BLOCKED_LABEL[pub.approve_blocked] ?? pub.approve_blocked}</p>
              ))}
              <p className="text-xs text-muted-foreground">Ligação às métricas: {pub.correlation_id}{pub.lineage_id ? ` · linhagem ${pub.lineage_id}` : " · ainda não publicada"}</p>
            </section>
          )}

          {pub && editable && (
            <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); cancel(); }}>
              <h3 className="font-semibold">Cancelar publicação</h3>
              <Input aria-label="Motivo do cancelamento" placeholder="Motivo" value={cancelReason} maxLength={500} onChange={(e) => setCancelReason(e.target.value)} />
              <Button type="submit" variant="outline" disabled={busy || cancelReason.trim().length < 3}>Cancelar publicação</Button>
            </form>
          )}
        </div>
      </SheetContent>

      {confirmApprove && pub && (
        <Dialog open onOpenChange={(v) => { if (!v) setConfirmApprove(false); }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Aprovar esta publicação?</DialogTitle>
              <DialogDescription>Aprovas exatamente isto (revisão {pub.revision}). Se alguma coisa mudar depois, a aprovação deixa de valer.</DialogDescription>
            </DialogHeader>
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
              <dt className="text-muted-foreground">Guião</dt><dd>{pub.content_n} · versão {pub.version_no}{pub.variant ? ` · ${pub.variant.label}` : " · original"}</dd>
              <dt className="text-muted-foreground">Destino</dt><dd>@{pub.account_handle} · {PLATFORM_LABEL[pub.platform]}</dd>
              <dt className="text-muted-foreground">Hora</dt><dd>{dayTitle(pub.local_day)} às {pub.local_time} ({tz})</dd>
              <dt className="text-muted-foreground">Legenda</dt><dd className="line-clamp-4 whitespace-pre-wrap">{pub.caption || "Sem legenda"}</dd>
              <dt className="text-muted-foreground">Hashtags</dt><dd>{pub.hashtags.join(" ") || "Sem hashtags"}</dd>
            </dl>
            <DialogFooter>
              <Button variant="ghost" onClick={() => setConfirmApprove(false)}>Voltar</Button>
              <Button onClick={approve} disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Aprovar</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </Sheet>
  );
}

/** VAR-01: variante = o que muda em cada um dos 5 elementos. Avisa enquanto se escreve; o servidor bloqueia irmãs repetidas. */
function VariantForm({ access, contentId, versionId, detail, onCancel, onSaved, onArchived }: {
  access: Access; contentId: string; versionId: string; detail: ContentDetail;
  onCancel: () => void; onSaved: (d: ContentDetail, label: string) => void; onArchived: (d: ContentDetail) => void;
}) {
  const [label, setLabel] = useState("");
  const [platform, setPlatform] = useState<Platform | "">("");
  const [style, setStyle] = useState("");
  const [el, setEl] = useState<Elements>({});
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const clean = cleanElements(el);
  const changes = variantDiff(clean, {});
  const close = detail.variants.filter((v) => !v.archived && (!platform || !v.platform || v.platform === platform) && variantDiff(clean, v.elements) < 2);
  const submit = async () => {
    setBusy(true); setErr("");
    const s = detail.styles.find((x) => x.key === style);
    try {
      const d = await saveVariant(access, { content_id: contentId, content_version_id: versionId, label: label.trim(), platform: platform || null,
        edit_style_key: s?.key ?? null, edit_style_version: s?.version ?? null, elements: clean });
      onSaved(d, label.trim());
    } catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  const archive = async (id: string) => {
    setBusy(true); setErr("");
    try { onArchived(await archiveVariant(access, id)); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <section className="flex flex-col gap-3 rounded-lg border p-3" aria-labelledby="variant-form-title">
      <h3 id="variant-form-title" className="font-semibold">Nova variante</h3>
      <p className="text-xs text-muted-foreground">Só conta como nova se mudar pelo menos 2 de 5 elementos. Layout, cor, letra e troca de imagem sem tese nova contam zero. Uma variante não se edita: cria outra.</p>
      <label className="flex flex-col gap-1">Nome<Input value={label} maxLength={80} onChange={(e) => setLabel(e.target.value)} placeholder="Ex.: Segmento 2 com narração" /></label>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="flex flex-col gap-1">Plataforma
          <select className={selectCls} value={platform} onChange={(e) => setPlatform(e.target.value as Platform | "")}>
            <option value="">Qualquer</option>
            {PLATFORMS.map((p) => <option key={p} value={p}>{PLATFORM_LABEL[p]}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Estilo de edição
          <select className={selectCls} value={style} onChange={(e) => setStyle(e.target.value)}>
            <option value="">Sem estilo</option>
            {detail.styles.map((s) => <option key={s.key} value={s.key}>{s.key} · {s.name} (v{s.version})</option>)}
          </select>
        </label>
      </div>
      {ELEMENT_KEYS.map((k) => (
        <label key={k} className="flex flex-col gap-1">{ELEMENT_LABEL[k]}
          <Input value={el[k] ?? ""} maxLength={300} placeholder="Igual ao original" onChange={(e) => setEl({ ...el, [k]: e.target.value })} />
          <span className="text-xs text-muted-foreground">{ELEMENT_HINT[k]}</span>
        </label>
      ))}
      <p className={cn("text-sm", changes >= 2 ? "text-emerald-600 dark:text-emerald-400" : "text-amber-600 dark:text-amber-400")}>
        Muda {changes} de 5 elementos: {changes >= 2 ? "conta como variante nova." : "não conta como variante nova."}
      </p>
      {close.length > 0 && (
        <p className="text-sm text-amber-600 dark:text-amber-400">
          Difere em menos de 2 elementos de: {close.map((v) => v.label).join(", ")}. {platform ? "Na mesma plataforma o servidor recusa." : ""}
        </p>
      )}
      {detail.variants.filter((v) => !v.archived).length > 0 && (
        <details>
          <summary className="cursor-pointer text-xs">Variantes deste guião</summary>
          <ul className="mt-1 flex flex-col gap-1 text-xs">
            {detail.variants.filter((v) => !v.archived).map((v) => (
              <li key={v.id} className="flex items-center justify-between gap-2">
                <span>{v.label}{v.platform ? ` · ${PLATFORM_LABEL[v.platform]}` : ""} · muda {v.changes} de 5</span>
                <Button type="button" size="sm" variant="ghost" disabled={busy} onClick={() => archive(v.id)}>Arquivar</Button>
              </li>
            ))}
          </ul>
        </details>
      )}
      {err && <p role="alert" className="text-destructive">{err}</p>}
      <div className="flex gap-2">
        <Button type="button" variant="ghost" onClick={onCancel}>Fechar</Button>
        <Button type="button" disabled={busy || !label.trim()} onClick={submit}>{busy && <Loader2Icon className="animate-spin" />} Criar variante</Button>
      </div>
    </section>
  );
}
