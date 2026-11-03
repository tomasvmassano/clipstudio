"use client";

import { useEffect, useState } from "react";
import { CheckIcon, Loader2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Notice, selectCls } from "@/components/portal/portal-shared";
import type { Access } from "@/lib/access";
import { transitionContent } from "@/lib/data";
import { fetchReworkReasons, transitionReasoned, type ReworkReason } from "@/lib/learn";
import { approvePublication, type Publication } from "@/lib/pub";
import { BLOCKED_LABEL, PLATFORM_LABEL } from "@/lib/pub-rules";
import type { PortalScript, PublicationsBlock, ScriptsBlock } from "@/lib/portal";
import { FORMATO_LABEL } from "@/lib/types";

type Msg = { kind: "ok" | "err"; text: string } | null;
const errText = (e: unknown) => (e as Error).message || "Não consegui concluir. Tenta de novo.";

/** Guiões em revisão que esta pessoa pode aprovar. As decisões passam por content_transition(_reasoned), sem regras novas. */
export function ScriptApprovals({ access, block, onChanged }: { access: Access; block: ScriptsBlock; onChanged: () => void }) {
  const [msg, setMsg] = useState<Msg>(null);
  if (block.items.length === 0) return <p className="text-sm text-muted-foreground">Não há guiões à espera da tua aprovação.</p>;
  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-muted-foreground">
        {block.total} à espera{block.over_48h ? `, ${block.over_48h} há mais de 48 h` : ""}{block.total > block.items.length ? ` (mostro os ${block.items.length} mais próximos)` : ""}.
      </p>
      <Notice msg={msg} />
      {block.items.map((g) => (
        <ScriptItem key={g.id} access={access} g={g} canReject={block.can_reject} byCategory={block.reasons_by_category}
          onDone={(text) => { setMsg({ kind: "ok", text }); onChanged(); }}
          onError={(e) => { setMsg({ kind: "err", text: errText(e) }); onChanged(); }} />
      ))}
    </div>
  );
}

function ScriptItem({ access, g, canReject, byCategory, onDone, onError }: {
  access: Access; g: PortalScript; canReject: boolean; byCategory: boolean; onDone: (t: string) => void; onError: (e: unknown) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<"changes_requested" | "rejected" | null>(null);
  const run = async (fn: () => Promise<unknown>, ok: string) => {
    setBusy(true);
    try { await fn(); onDone(ok); } catch (e) { onError(e); } finally { setBusy(false); }
  };
  return (
    <article className="flex min-w-0 flex-col gap-2 rounded-lg border p-3" data-portal-script={g.id}>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="font-medium">Guião {g.n}</span>
        <span className="text-muted-foreground">{g.date.split("-").reverse().join("/")}</span>
        {g.formato && <Badge variant="outline">{FORMATO_LABEL[g.formato as keyof typeof FORMATO_LABEL] ?? g.formato}</Badge>}
        {g.version_no !== null && <Badge variant="outline">versão {g.version_no}</Badge>}
        <span className="text-xs text-muted-foreground">em revisão desde {g.waiting_local}{g.over_48h ? " (mais de 48 h)" : ""}</span>
      </div>
      {g.tema && <p className="text-sm font-medium">{g.tema}</p>}
      {g.hooks.length > 0 && (
        <ol className="list-decimal pl-5 text-sm">{g.hooks.map((h, i) => <li key={i}>{h}</li>)}</ol>
      )}
      {g.corpo && <p className="whitespace-pre-wrap text-sm text-muted-foreground">{g.corpo}</p>}
      {g.cta && <p className="text-sm"><span className="text-muted-foreground">CTA: </span>{g.cta}</p>}
      {mode ? (
        <ReasonInline access={access} mode={mode} byCategory={byCategory} busy={busy} onCancel={() => setMode(null)}
          onSubmit={(reason, code) => run(
            () => code ? transitionReasoned(access, g.id, mode, reason, code, g.lock_version) : transitionContent(access, g.id, mode, reason, g.lock_version),
            mode === "rejected" ? `Guião ${g.n} rejeitado.` : `Pediste alterações ao guião ${g.n}.`)} />
      ) : (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" disabled={busy} onClick={() => run(() => transitionContent(access, g.id, "approved", undefined, g.lock_version), `Guião ${g.n} aprovado.`)}>
            {busy ? <Loader2Icon className="animate-spin" /> : <CheckIcon />} Aprovar guião
          </Button>
          {canReject && (
            <>
              <Button size="sm" variant="outline" disabled={busy} onClick={() => setMode("changes_requested")}>Pedir alterações</Button>
              <Button size="sm" variant="ghost" disabled={busy} onClick={() => setMode("rejected")}>Rejeitar</Button>
            </>
          )}
        </div>
      )}
    </article>
  );
}

/** Motivo obrigatório; com learn.rework e categorias deste cliente, a categoria também (FR-17-10). */
function ReasonInline({ access, mode, byCategory, busy, onCancel, onSubmit }: {
  access: Access; mode: "changes_requested" | "rejected"; byCategory: boolean; busy: boolean;
  onCancel: () => void; onSubmit: (reason: string, code: string | null) => void;
}) {
  const [reason, setReason] = useState("");
  const [code, setCode] = useState("");
  const [reasons, setReasons] = useState<ReworkReason[] | null>(byCategory ? null : []);
  const [loadErr, setLoadErr] = useState(false);
  useEffect(() => {
    if (!byCategory) return;
    let alive = true;
    fetchReworkReasons(access)
      .then((l) => { if (alive) setReasons(l.enabled ? l.reasons.filter((r) => r.active && r.applies_to.includes("guiao")) : []); })
      .catch(() => { if (alive) { setLoadErr(true); setReasons([]); } });
    return () => { alive = false; };
  }, [access, byCategory]);
  const withCategory = !!reasons?.length;
  const rejected = mode === "rejected";
  const ready = reasons !== null && !!reason.trim() && (!withCategory || !!code);
  return (
    <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); if (ready) onSubmit(reason.trim(), withCategory ? code : null); }}>
      <div className="flex flex-wrap gap-2">
        {withCategory && (
          <select className={selectCls} value={code} onChange={(e) => setCode(e.target.value)} required
            aria-label={rejected ? "Categoria da rejeição" : "Categoria do pedido de alterações"}>
            <option value="">Categoria…</option>
            {reasons!.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}
          </select>
        )}
        <Input className="min-w-[12rem] flex-1" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus required maxLength={1000}
          aria-label={rejected ? "Motivo da rejeição" : "O que tem de mudar"} placeholder={rejected ? "Porque não avança?" : "O que tem de mudar?"} />
        <Button size="sm" type="submit" variant={rejected ? "destructive" : "default"} disabled={busy || !ready}>
          {(busy || reasons === null) && <Loader2Icon className="animate-spin" />} {rejected ? "Rejeitar" : "Pedir alterações"}
        </Button>
        <Button size="sm" type="button" variant="ghost" onClick={onCancel}>Cancelar</Button>
      </div>
      {loadErr && <p className="text-xs text-muted-foreground" role="status">Não consegui carregar as categorias; segue só com o texto.</p>}
    </form>
  );
}

/** Publicações planeadas à espera da parte do cliente. A aprovação é pub_approve (política, autoaprovação, revisão vista). */
export function PublicationApprovals({ access, block, tz, onChanged }: { access: Access; block: PublicationsBlock; tz: string; onChanged: () => void }) {
  const [msg, setMsg] = useState<Msg>(null);
  const [confirm, setConfirm] = useState<Publication | null>(null);
  const [busy, setBusy] = useState(false);
  const approve = async (p: Publication) => {
    setBusy(true);
    try {
      const r = await approvePublication(access, p.id, p.revision);
      setMsg({ kind: "ok", text: r.status === "aprovada" ? `Aprovada. Fica pronta para @${p.account_handle} a ${p.local_day.split("-").reverse().join("/")} às ${p.local_time}.`
        : "A tua aprovação ficou registada; falta a outra parte." });
    } catch (e) { setMsg({ kind: "err", text: errText(e) }); }
    finally { setBusy(false); setConfirm(null); onChanged(); }
  };
  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-muted-foreground">{block.publish_unavailable_reason}</p>
      {!block.individual && <p className="text-sm text-muted-foreground">Aprovar publicações exige entrar com a tua conta pessoal (o código de equipa só lê).</p>}
      <Notice msg={msg} />
      {block.items.length === 0 ? <p className="text-sm text-muted-foreground">Não há publicações à espera da tua parte.</p> : block.items.map((p) => (
        <article key={p.id} className="flex min-w-0 flex-col gap-2 rounded-lg border p-3" data-portal-pub={p.id}>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="font-medium">{p.local_day.split("-").reverse().join("/")} às {p.local_time}</span>
            <Badge variant="outline">{PLATFORM_LABEL[p.platform]}</Badge>
            <span>@{p.account_handle}</span>
            <span className="text-muted-foreground">Guião {p.content_n} · versão {p.version_no}{p.variant ? ` · ${p.variant.label}` : ""}{p.kind === "republicacao" ? " · republicação" : ""}</span>
          </div>
          {p.content_hook && <p className="text-sm">{p.content_hook}</p>}
          <p className="line-clamp-4 whitespace-pre-wrap text-sm text-muted-foreground">{p.caption || "Sem legenda"}</p>
          {p.hashtags.length > 0 && <p className="text-xs text-muted-foreground">{p.hashtags.join(" ")}</p>}
          {p.conflicts.filter((c) => c.code !== "versao_por_aprovar" || !p.version_approved).map((c) => (
            <p key={c.code} className={c.severity === "bloqueia" ? "text-xs text-destructive" : "text-xs text-muted-foreground"}>{c.message}</p>
          ))}
          {p.can_approve ? (
            <div><Button size="sm" onClick={() => setConfirm(p)}><CheckIcon /> Aprovar publicação</Button></div>
          ) : p.approve_blocked && (p.approve_blocked !== "sem_capacidade" || block.individual) && (
            <p className="text-xs text-muted-foreground">
              {p.approve_blocked === "sem_capacidade" ? "Não tens permissão para aprovar publicações neste cliente." : BLOCKED_LABEL[p.approve_blocked] ?? p.approve_blocked}
            </p>
          )}
        </article>
      ))}
      {confirm && (
        <Dialog open onOpenChange={(v) => { if (!v) setConfirm(null); }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Aprovar esta publicação?</DialogTitle>
              <DialogDescription>Aprovas exatamente isto (revisão {confirm.revision}). Se alguma coisa mudar depois, a aprovação deixa de valer.</DialogDescription>
            </DialogHeader>
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
              <dt className="text-muted-foreground">Guião</dt><dd>{confirm.content_n} · versão {confirm.version_no}{confirm.variant ? ` · ${confirm.variant.label}` : " · original"}</dd>
              <dt className="text-muted-foreground">Destino</dt><dd>@{confirm.account_handle} · {PLATFORM_LABEL[confirm.platform]}</dd>
              <dt className="text-muted-foreground">Hora</dt><dd>{confirm.local_day.split("-").reverse().join("/")} às {confirm.local_time} ({tz})</dd>
              <dt className="text-muted-foreground">Legenda</dt><dd className="line-clamp-4 whitespace-pre-wrap">{confirm.caption || "Sem legenda"}</dd>
              <dt className="text-muted-foreground">Hashtags</dt><dd>{confirm.hashtags.join(" ") || "Sem hashtags"}</dd>
            </dl>
            <DialogFooter>
              <Button variant="ghost" onClick={() => setConfirm(null)}>Voltar</Button>
              <Button onClick={() => approve(confirm)} disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Aprovar</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}
