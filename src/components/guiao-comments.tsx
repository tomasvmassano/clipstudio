"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckIcon, Loader2Icon, MessageSquarePlusIcon, ReplyIcon, RotateCcwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { useSession } from "@/components/session-provider";
import { addComment, blockLabel, fetchComments, resolveComment, type CommentBlock, type CommentThread, type ContentComment } from "@/lib/comments";
import type { Guiao } from "@/lib/types";

const fmt = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

type Target = { block: CommentBlock; quote: string | null };

/** Revisão de um guião com comentários presos a um bloco e a uma frase (FR-05-02, FR-02-02).
 *  Carrega numa frase para comentar essa frase; os comentários ficam com a versão em que foram feitos. */
export function CommentsSheet({ g, open, onOpenChange, onCount }: {
  g: Guiao; open: boolean; onOpenChange: (v: boolean) => void; onCount?: (openCount: number) => void;
}) {
  const { access } = useSession();
  const [t, setT] = useState<CommentThread | null>(null);
  const [err, setErr] = useState("");
  const [target, setTarget] = useState<Target>({ block: "geral", quote: null });
  const [body, setBody] = useState("");
  const [reply, setReply] = useState<{ id: string; body: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [showResolved, setShowResolved] = useState(false);

  const load = useCallback(async () => {
    if (!access) return;
    try { const x = await fetchComments(access, g.id); setT(x); setErr(""); onCount?.(x.comments.filter((c) => !c.parent_id && !c.resolved_at).length); }
    catch (e) { setErr((e as Error).message); }
  }, [access, g.id, onCount]);
  useEffect(() => { if (open) queueMicrotask(() => void load()); }, [open, load, g.lock_version]);

  const roots = useMemo(() => (t?.comments ?? []).filter((c) => !c.parent_id), [t]);
  const replies = useMemo(() => {
    const m = new Map<string, ContentComment[]>();
    for (const c of t?.comments ?? []) if (c.parent_id) m.set(c.parent_id, [...(m.get(c.parent_id) ?? []), c]);
    return m;
  }, [t]);
  const byBlock = useCallback((b: string) => roots.filter((c) => c.block === b && (showResolved || !c.resolved_at)), [roots, showResolved]);
  const openCount = roots.filter((c) => !c.resolved_at).length;
  const resolvedCount = roots.length - openCount;

  const send = async () => {
    if (!access || !body.trim()) return;
    setBusy(true); setErr("");
    try { await addComment(access, g.id, { block: target.block, quote: target.quote, body }); setBody(""); setTarget({ block: "geral", quote: null }); await load(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  const sendReply = async () => {
    if (!access || !reply?.body.trim()) return;
    setBusy(true); setErr("");
    try { await addComment(access, g.id, { block: "geral", body: reply.body, parent: reply.id }); setReply(null); await load(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  const toggle = async (c: ContentComment) => {
    if (!access) return;
    setBusy(true); setErr("");
    try { await resolveComment(access, c.id, !c.resolved_at); await load(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  const canComment = !!t?.can.comment && g.editorial_status !== "archived";
  const pick = (block: CommentBlock, quote: string | null) => { if (canComment) setTarget({ block, quote }); };

  // funções de render (não componentes): assim a caixa de resposta não perde o foco a cada tecla
  const thread = (c: ContentComment) => {
    const mine = !!t?.me && c.author_id === t.me;
    return (
      <div key={c.id} className={cn("rounded-md border bg-background p-2 text-sm", c.resolved_at && "opacity-60")}>
        {c.quote && <p className="mb-1 border-l-2 border-amber-500/70 pl-2 text-xs italic text-muted-foreground">“{c.quote}”</p>}
        <p className="whitespace-pre-line">{c.body}</p>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
          <span>{c.author}{c.author_kind === "legacy_code" ? " (código)" : ""} · {fmt(c.at)}</span>
          {c.version_no != null && <span>{c.on_current ? `v${c.version_no}` : `numa versão anterior (v${c.version_no})`}</span>}
          {c.resolved_at && <span>resolvido{c.resolved_by ? ` por ${c.resolved_by}` : ""}</span>}
        </div>
        {(replies.get(c.id) ?? []).map((r) => (
          <div key={r.id} className="mt-2 border-l pl-2">
            <p className="whitespace-pre-line">{r.body}</p>
            <span className="text-xs text-muted-foreground">{r.author}{r.author_kind === "legacy_code" ? " (código)" : ""} · {fmt(r.at)}</span>
          </div>
        ))}
        <div className="mt-1 flex gap-1">
          {canComment && !c.resolved_at && (
            <Button size="xs" variant="ghost" onClick={() => setReply({ id: c.id, body: "" })}><ReplyIcon /> Responder</Button>
          )}
          {(t?.can.resolve || mine) && (
            <Button size="xs" variant="ghost" disabled={busy} onClick={() => void toggle(c)}>
              {c.resolved_at ? <><RotateCcwIcon /> Reabrir</> : <><CheckIcon /> Resolver</>}
            </Button>
          )}
        </div>
        {reply?.id === c.id && (
          <div className="mt-2 flex flex-col gap-1">
            <Textarea aria-label="Resposta" rows={2} value={reply.body} onChange={(e) => setReply({ id: c.id, body: e.target.value })} autoFocus />
            <div className="flex gap-1">
              <Button size="xs" disabled={busy || !reply.body.trim()} onClick={() => void sendReply()}>{busy && <Loader2Icon className="animate-spin" />} Responder</Button>
              <Button size="xs" variant="ghost" onClick={() => setReply(null)}>Cancelar</Button>
            </div>
          </div>
        )}
      </div>
    );
  };

  const blockView = (block: CommentBlock, label: string, children: React.ReactNode) => {
    const list = byBlock(block);
    return (
      <section key={block} className={cn("flex flex-col gap-1.5 rounded-lg p-2", target.block === block && "bg-amber-500/5 ring-1 ring-amber-500/40")}>
        <div className="flex items-center justify-between gap-2">
          <h4 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</h4>
          {canComment && (
            <Button size="xs" variant="ghost" aria-label={`Comentar ${label}`} onClick={() => pick(block, null)}><MessageSquarePlusIcon /> Comentar</Button>
          )}
        </div>
        {children}
        {list.map((c) => thread(c))}
      </section>
    );
  };

  const line = (block: CommentBlock, text: string, key: string | number) => (
    <button
      key={key} type="button" disabled={!canComment}
      className={cn("w-full rounded px-1 text-left text-sm leading-relaxed", canComment && "hover:bg-amber-500/10",
        target.block === block && target.quote === text && "bg-amber-500/15")}
      title={canComment ? "Comentar esta frase" : undefined}
      onClick={() => pick(block, text)}
    >{text}</button>
  );

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>Revisão do guião {g.n}</SheetTitle>
          <SheetDescription>
            Carrega numa frase para a comentar. Os comentários ficam presos à versão em que foram feitos; resolve-os quando o texto já os resolver.
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-3 px-4 pb-6">
          {err && <p className="text-sm text-destructive" role="alert">{err} <Button size="sm" variant="link" onClick={() => void load()}>Tentar de novo</Button></p>}
          {!t && !err && <Skeleton className="h-64 w-full" />}
          {t && (
            <>
              <div className="flex flex-wrap items-center gap-2 text-xs">
                <Badge variant={openCount ? "secondary" : "outline"}>{openCount} por resolver</Badge>
                {resolvedCount > 0 && (
                  <button type="button" className="underline underline-offset-2" onClick={() => setShowResolved((v) => !v)}>
                    {showResolved ? "Esconder" : "Mostrar"} {resolvedCount} resolvido{resolvedCount > 1 ? "s" : ""}
                  </button>
                )}
              </div>
              {g.hooks.map((h, i) => blockView(`hook_${i + 1}`, `Hook ${i + 1}`, line(`hook_${i + 1}`, h.text, 0)))}
              {blockView("corpo", "Corpo", g.corpo.split("\n").filter((l) => l.trim()).map((l, i) => line("corpo", l, i)))}
              {g.cta && blockView("cta", "CTA", line("cta", g.cta, 0))}
              {g.notas && blockView("notas", "Notas", line("notas", g.notas, 0))}
              {blockView("geral", "Geral", <span className="text-xs text-muted-foreground">Sobre o guião todo.</span>)}

              {canComment ? (
                <div className="sticky bottom-0 flex flex-col gap-2 border-t bg-popover pt-3 pb-1">
                  <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span>A comentar: <b className="text-foreground">{blockLabel(target.block)}</b></span>
                    {target.quote && <span className="line-clamp-1 italic">“{target.quote}”</span>}
                    {(target.block !== "geral" || target.quote) && (
                      <button type="button" className="underline" onClick={() => setTarget({ block: "geral", quote: null })}>limpar</button>
                    )}
                  </div>
                  <Textarea aria-label="Comentário" rows={3} maxLength={4000} value={body} onChange={(e) => setBody(e.target.value)}
                    placeholder="O que mudavas e porquê?" onKeyDown={(e) => { if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) void send(); }} />
                  <div><Button disabled={busy || !body.trim()} onClick={() => void send()}>{busy && <Loader2Icon className="animate-spin" />} Comentar</Button></div>
                </div>
              ) : (
                <p className="text-xs text-muted-foreground">{g.editorial_status === "archived" ? "Guião arquivado: os comentários ficam só para consulta." : "Tens acesso de leitura: vês os comentários mas não comentas."}</p>
              )}
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
