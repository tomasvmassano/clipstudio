"use client";

/* Separador Comentários da tab Reacts (W10-26, PRD §47 REACT-08). Comentários dos Reels do cliente que dão vídeos novos. */

import { useCallback, useEffect, useState } from "react";
import { BookmarkIcon, CheckIcon, ExternalLinkIcon, Loader2Icon, MessageSquareIcon, MicIcon, RotateCwIcon, StarIcon, UndoIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WsLink } from "@/components/ws-link";
import type { Access } from "@/lib/access";
import { decideComment, fetchComments, recordComment, type CommentItem, type CommentList, type CommentTab } from "@/lib/reacts";
import {
  COMMENT_PART_LABELS, COMMENT_REJECT_REASONS, commentReasonLabel, engagement, kindLabel, KINDS, nextRun, reelLink, type CommentKind,
} from "@/lib/comments-format";
import { guiaoHref, scoreTone } from "@/lib/reacts-format";
import { cn } from "@/lib/utils";

const fmtWhen = (d: string | Date | null) => (d ? new Date(d).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");
const SUBTABS: { v: CommentTab; label: string }[] = [
  { v: "open", label: "A decidir" }, { v: "saved", label: "Guardados" }, { v: "recorded", label: "Gravados" }, { v: "rejected", label: "Rejeitados" },
];

export function CommentsTab({ access }: { access: Access }) {
  const [tab, setTab] = useState<CommentTab>("open");
  const [kind, setKind] = useState<CommentKind | null>(null);
  const [data, setData] = useState<CommentList | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [rejecting, setRejecting] = useState<CommentItem | null>(null);
  const [rev, setRev] = useState(0);
  const load = useCallback(() => { setLoading(true); setError(""); setRev((n) => n + 1); }, []);
  useEffect(() => {
    let alive = true;
    fetchComments(access, tab, kind)
      .then((d) => { if (alive) { setData(d); setError(""); } })
      .catch((e: Error) => { if (alive) setError(e.message); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [access, tab, kind, rev]);

  const replace = (it: CommentItem) => {
    setData((d) => (d ? { ...d, items: it.status === tab ? d.items.map((x) => (x.id === it.id ? it : x)) : d.items.filter((x) => x.id !== it.id) } : d));
  };
  const pick = (t: CommentTab, k: CommentKind | null) => { setTab(t); setKind(k); setLoading(true); };
  const next = nextRun(data?.last_run);

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        De 3 em 3 dias o agente lê os comentários dos Reels do cliente e traz os que dão vídeo novo: quem discorda (respondemos com vídeo), quem concorda e acrescenta, quem traz outro ponto de vista e as perguntas que merecem um vídeo inteiro. Responde-se à ideia, nunca à pessoa.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <ToggleGroup value={[tab]} onValueChange={(v) => { const x = (v as string[])[0] as CommentTab | undefined; if (x) pick(x, kind); }} variant="outline" size="sm" className="flex-wrap">
          {SUBTABS.map((t) => (
            <ToggleGroupItem key={t.v} value={t.v}>
              {t.label}{data ? <span className="ml-1 tabular-nums text-muted-foreground">{data.counts[t.v] ?? 0}</span> : null}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
      </div>
      <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por tipo de comentário">
        <Button size="sm" variant={kind === null ? "secondary" : "ghost"} aria-pressed={kind === null} onClick={() => pick(tab, null)}>Todos</Button>
        {KINDS.map((k) => (
          <Button key={k.value} size="sm" variant={kind === k.value ? "secondary" : "ghost"} aria-pressed={kind === k.value} title={k.hint} onClick={() => pick(tab, k.value)}>
            {k.label}{data?.kinds && kind === null && data.kinds[k.value] ? <span className="ml-1 tabular-nums text-muted-foreground">{data.kinds[k.value]}</span> : null}
          </Button>
        ))}
      </div>

      {loading && !data && (
        <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar comentários">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-36 w-full" />)}</div>
      )}
      {error && (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{error}</span><Button size="sm" variant="outline" onClick={load}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      )}
      {data && !error && (
        <div className={cn("flex flex-col gap-3", loading && "opacity-60")} aria-busy={loading}>
          <p className="text-xs text-muted-foreground">
            {data.last_run ? <>Última análise: {fmtWhen(data.last_run)}. Próxima por volta de {fmtWhen(next)}.</> : <>O agente ainda não analisou comentários deste cliente.</>}
            {tab === "open" && " Ordenado pela nota da IA."}
          </p>
          {data.items.length === 0 && (
            <div aria-live="polite">
              <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">
                {tab === "open" ? "Não há comentários por decidir." : tab === "saved" ? "Nada guardado." : tab === "recorded" ? "Ainda nenhum comentário passou a guião." : "Nenhum comentário rejeitado."}
                {kind && " Experimenta tirar o filtro."}
              </CardContent></Card>
            </div>
          )}
          {data.items.map((it) => (
            <CommentCard key={it.id} access={access} it={it} can={data.can} onChange={replace} onReject={() => setRejecting(it)} onError={setError} />
          ))}
        </div>
      )}
      <RejectCommentDialog access={access} item={rejecting} onClose={() => setRejecting(null)} onDone={(it) => { setRejecting(null); replace(it); load(); }} />
    </div>
  );
}

function CommentCard({ access, it, can, onChange, onReject, onError }: {
  access: Access; it: CommentItem; can: CommentList["can"]; onChange: (it: CommentItem) => void; onReject: () => void; onError: (m: string) => void;
}) {
  const [busy, setBusy] = useState("");
  const [more, setMore] = useState(false);
  const [recorded, setRecorded] = useState<string | null>(it.content_id);
  const ai = it.ai ?? {};
  const act = async (name: string, f: () => Promise<CommentItem>) => {
    setBusy(name);
    try { onChange(await f()); } catch (e) { onError((e as Error).message); } finally { setBusy(""); }
  };
  const record = async () => {
    setBusy("record");
    try { const r = await recordComment(access, it.id); setRecorded(r.content_id); onChange(r.item); } catch (e) { onError((e as Error).message); } finally { setBusy(""); }
  };
  const href = guiaoHref(recorded);
  const reel = reelLink(it.reel_url);
  const tone = scoreTone(it.score);
  const eng = engagement(it.likes, it.replies);
  return (
    <Card>
      <CardContent className="flex flex-col gap-3 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <span className={cn("inline-flex items-center rounded-md px-2 py-0.5 text-sm font-semibold tabular-nums",
            tone === "alta" && "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
            tone === "media" && "bg-amber-500/15 text-amber-700 dark:text-amber-400",
            (tone === "baixa" || tone === "sem") && "bg-muted text-muted-foreground")} title="Nota da IA: dá um vídeo novo?">
            {it.score == null ? "sem nota" : `${it.score}/100`}
          </span>
          <Badge variant={it.kind === "discorda" ? "destructive" : "secondary"}>{kindLabel(it.kind)}</Badge>
          {it.risk_level === "alto" && <Badge variant="destructive">Risco alto</Badge>}
          {it.risk_level === "medio" && <Badge variant="outline">Risco médio</Badge>}
          {eng && <span className="text-xs text-muted-foreground">{eng}</span>}
          {it.posted_at && <span className="text-xs text-muted-foreground">{fmtWhen(it.posted_at)}</span>}
        </div>

        <blockquote className="flex gap-2 rounded-md border-l-2 border-primary/60 bg-muted/40 px-3 py-2 text-sm">
          <MessageSquareIcon className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden />
          <span className="whitespace-pre-line">{it.text}</span>
        </blockquote>
        <p className="text-xs text-muted-foreground">
          {it.author ? <>por @{it.author} (pessoa privada: não mostrar o nome no vídeo sem autorização)</> : <>autor desconhecido</>}
          {reel && <> · <a href={reel} target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-1 hover:underline">no reel{it.reel_account ? ` de @${it.reel_account}` : ""} <ExternalLinkIcon className="size-3" /></a></>}
        </p>

        {ai.ideia && <p className="text-sm"><span className="font-medium">Ideia de vídeo: </span>{ai.ideia}</p>}
        {ai.angulo && <p className="text-sm"><span className="font-medium">Ângulo: </span>{ai.angulo}</p>}
        {ai.hooks && ai.hooks.length > 0 && (
          <ul className="flex flex-col gap-1 text-sm">
            {ai.hooks.slice(0, 3).map((h, i) => <li key={i} className="rounded-md bg-muted/60 px-2 py-1">“{h.text}”</li>)}
          </ul>
        )}
        {ai.risk_flags && ai.risk_flags.length > 0 && <p className="text-xs text-destructive">Atenção: {ai.risk_flags.join(" · ")}</p>}

        {more && (
          <div className="flex flex-col gap-3 rounded-md border p-3 text-sm">
            {ai.parts && (
              <div className="grid gap-1.5 sm:grid-cols-2">
                {Object.entries(ai.parts).map(([k, v]) => (
                  <div key={k} className="flex items-center gap-2 text-xs">
                    <span className="w-40 shrink-0 text-muted-foreground">{COMMENT_PART_LABELS[k] ?? k}</span>
                    <span className="h-1.5 flex-1 overflow-hidden rounded bg-muted"><span className="block h-full bg-primary" style={{ width: `${Math.max(0, Math.min(100, Number(v) || 0))}%` }} /></span>
                    <span className="w-8 text-right tabular-nums">{v}</span>
                  </div>
                ))}
              </div>
            )}
            {ai.porque && <p><span className="font-medium">Porquê: </span>{ai.porque}</p>}
            {ai.resposta && <div><p className="font-medium">Rascunho da resposta</p><p className="whitespace-pre-line text-muted-foreground">{ai.resposta}</p></div>}
            {it.reel_caption && <div><p className="font-medium">Legenda do reel</p><p className="whitespace-pre-line text-muted-foreground">{it.reel_caption}</p></div>}
            {ai.model && <p className="text-xs text-muted-foreground">Avaliado por {ai.model}{ai.prompt_version ? ` · ${ai.prompt_version}` : ""} · {fmtWhen(ai.evaluated_at ?? null)}</p>}
          </div>
        )}

        {it.status === "rejected" && <p className="text-xs text-muted-foreground">Rejeitado por {it.decided_label ?? "—"}: {commentReasonLabel(it.reject_reason)}{it.decision_note ? ` · ${it.decision_note}` : ""}</p>}

        <div className="flex flex-wrap items-center gap-2">
          {can.record && (it.status === "open" || it.status === "saved") && !recorded && (
            <Button size="sm" onClick={record} disabled={!!busy}>{busy === "record" ? <Loader2Icon className="animate-spin" /> : <MicIcon />} Gravar resposta</Button>
          )}
          {href && <Button size="sm" variant="outline" nativeButton={false} render={<WsLink href={href} />}><CheckIcon /> Abrir guião</Button>}
          {can.decide && it.status === "open" && (
            <Button size="sm" variant="outline" onClick={() => act("save", () => decideComment(access, it.id, "save"))} disabled={!!busy}>
              {busy === "save" ? <Loader2Icon className="animate-spin" /> : <BookmarkIcon />} Guardar
            </Button>
          )}
          {can.decide && (it.status === "open" || it.status === "saved") && <Button size="sm" variant="ghost" onClick={onReject} disabled={!!busy}><XIcon /> Rejeitar</Button>}
          {can.decide && (it.status === "rejected" || it.status === "saved") && (
            <Button size="sm" variant="ghost" onClick={() => act("reopen", () => decideComment(access, it.id, "reopen"))} disabled={!!busy}><UndoIcon /> Voltar à fila</Button>
          )}
          {can.decide && (
            <div className="flex items-center" role="group" aria-label="A tua nota (ensina o agente)">
              {[1, 2, 3, 4, 5].map((n) => (
                <button key={n} type="button" disabled={!!busy} onClick={() => act("rate", () => decideComment(access, it.id, "rate", { rating: n }))} aria-label={`Nota ${n} de 5`} aria-pressed={it.rating === n}
                  className="p-0.5 text-muted-foreground hover:text-amber-500 disabled:opacity-50">
                  <StarIcon className={cn("size-4", it.rating != null && n <= it.rating && "fill-amber-400 text-amber-500")} />
                </button>
              ))}
            </div>
          )}
          <Button size="sm" variant="link" onClick={() => setMore((v) => !v)}>{more ? "Esconder detalhe" : "Ver avaliação completa"}</Button>
        </div>
      </CardContent>
    </Card>
  );
}

function RejectCommentDialog({ access, item, onClose, onDone }: { access: Access; item: CommentItem | null; onClose: () => void; onDone: (it: CommentItem) => void }) {
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [forId, setForId] = useState<number | null>(null);
  if ((item?.id ?? null) !== forId) { setForId(item?.id ?? null); setReason(""); setNote(""); setError(""); }
  const submit = async () => {
    if (!item || !reason) return;
    setBusy(true); setError("");
    try { onDone(await decideComment(access, item.id, "reject", { reason, note })); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <Dialog open={!!item} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Rejeitar este comentário</DialogTitle>
          <DialogDescription>O motivo ensina o agente a não trazer comentários parecidos.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Motivo">
          {COMMENT_REJECT_REASONS.map((r) => (
            <Button key={r.value} size="sm" variant={reason === r.value ? "default" : "outline"} role="radio" aria-checked={reason === r.value} onClick={() => setReason(r.value)}>{r.label}</Button>
          ))}
        </div>
        <Textarea rows={2} placeholder="Nota opcional" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={submit} disabled={!reason || busy}>{busy && <Loader2Icon className="animate-spin" />} Rejeitar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
