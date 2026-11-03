"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckIcon, ExternalLinkIcon, MessagesSquareIcon, RotateCwIcon, SearchIcon, Undo2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import type { Access } from "@/lib/access";
import {
  REVIEW_STATUS, addReviewComment, decideReview, fetchReview, fetchReviewList, resolveReviewComment, statusLabel, variantLabel,
  type ReviewDetail, type ReviewItem, type ReviewList, type ReviewStatus,
} from "@/lib/media-review";
import { driveLinks, fmtMoment, parseMoment } from "@/lib/media-time";

const tone = (s: ReviewStatus): "default" | "secondary" | "destructive" | "outline" =>
  s === "approved" ? "default" : s === "changes_requested" ? "destructive" : s === "rejected" ? "secondary" : "outline";
const when = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/** Revisão de vídeo (FR-05-03, CHG-006): vídeos por guião e hook, com o player da Drive, comentários por momento e decisão com motivo. */
export function VideoReviewPanel({ access }: { access: Access }) {
  const [status, setStatus] = useState<ReviewStatus[]>(["in_review", "changes_requested"]);
  const [q, setQ] = useState("");
  const [list, setList] = useState<ReviewList | null>(null);
  const [err, setErr] = useState("");
  const [open, setOpen] = useState<string | null>(null);

  const reload = useCallback(async () => {
    try { setList(await fetchReviewList(access, { status, q: q.trim() || undefined })); setErr(""); }
    catch (e) { setErr((e as Error).message); }
  }, [access, status, q]);
  useEffect(() => {
    const id = setTimeout(() => void reload(), q ? 300 : 0);
    return () => clearTimeout(id);
  }, [reload, q]);

  // agrupa por guião, pela ordem do servidor (dia, número, hook)
  const groups = useMemo(() => {
    const m = new Map<string, ReviewItem[]>();
    for (const it of list?.items ?? []) { const k = it.guiao?.id ?? it.asset_id; m.set(k, [...(m.get(k) ?? []), it]); }
    return [...m.values()];
  }, [list]);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-3 rounded-lg border p-3">
        <ToggleGroup multiple value={status} onValueChange={(v) => setStatus(v as ReviewStatus[])} variant="outline" size="sm" className="flex-wrap">
          {REVIEW_STATUS.map((s) => (
            <ToggleGroupItem key={s.v} value={s.v} aria-label={s.l}>
              {s.l}{list?.counts?.[s.v] != null && <span className="ml-1 tabular-nums text-muted-foreground">{list.counts[s.v]}</span>}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
        <div className="flex flex-wrap items-center gap-2">
          <label className="relative min-w-56 flex-1">
            <SearchIcon className="pointer-events-none absolute top-2 left-2 size-4 text-muted-foreground" />
            <Input aria-label="Pesquisar vídeos" className="h-8 pl-8" placeholder="Pesquisar tema ou ficheiro" value={q} maxLength={100} onChange={(e) => setQ(e.target.value)} />
          </label>
          <Button variant="outline" size="sm" onClick={() => void reload()}><RotateCwIcon /> Atualizar</Button>
        </div>
      </div>

      {err && <Alert variant="destructive"><AlertDescription>{err} <Button size="sm" variant="link" onClick={() => void reload()}>Tentar de novo</Button></AlertDescription></Alert>}
      {!list && !err && <div className="flex flex-col gap-3">{[1, 2].map((i) => <Skeleton key={i} className="h-28 w-full" />)}</div>}
      {list && groups.length === 0 && (
        <Alert><AlertDescription>{status.length === 0 ? "Escolhe pelo menos um estado." : "Nenhum vídeo com estes filtros."}</AlertDescription></Alert>
      )}
      {list && groups.length > 0 && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted-foreground">{list.items.length} {list.items.length === 1 ? "vídeo" : "vídeos"} em {groups.length} {groups.length === 1 ? "guião" : "guiões"}</p>
          {groups.map((g) => (
            <div key={g[0].guiao?.id ?? g[0].asset_id} className="flex flex-col gap-2 rounded-lg border p-3">
              <div className="flex flex-wrap items-baseline gap-2">
                {g[0].guiao && <span className="text-xs text-muted-foreground">Guião {g[0].guiao.n}</span>}
                <span className="font-medium">{g[0].guiao?.tema ?? g[0].title}</span>
              </div>
              <div className="grid gap-2 sm:grid-cols-3">
                {g.map((it) => (
                  <button key={it.asset_id} type="button" onClick={() => setOpen(it.asset_id)}
                    className="flex flex-col items-start gap-1 rounded-md border p-2 text-left text-sm transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring">
                    <div className="flex w-full items-center justify-between gap-2">
                      <span className="font-medium">{variantLabel(it.variant)}{it.style ? ` · ${it.style}` : ""}</span>
                      <Badge variant={tone(it.status)}>{statusLabel(it.status)}</Badge>
                    </div>
                    {it.guiao?.hook && <span className="line-clamp-2 text-xs text-muted-foreground">{it.guiao.hook}</span>}
                    <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
                      v{it.version} · <MessagesSquareIcon className="size-3" /> {it.open_comments} por resolver
                    </span>
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
      {open && <VideoSheet key={open} access={access} assetId={open} onClose={() => setOpen(null)} onChanged={() => void reload()} />}
    </div>
  );
}

function VideoSheet({ access, assetId, onClose, onChanged }: { access: Access; assetId: string; onClose: () => void; onChanged: () => void }) {
  const [ver, setVer] = useState<string | null>(null);
  const [d, setD] = useState<ReviewDetail | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  const [moment, setMoment] = useState("");
  const [body, setBody] = useState("");
  const [reason, setReason] = useState("");
  const [asking, setAsking] = useState<"changes_requested" | "rejected" | null>(null);

  const load = useCallback(async () => {
    try { setD(await fetchReview(access, assetId, ver)); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access, assetId, ver]);
  useEffect(() => { const t = setTimeout(() => void load(), 0); return () => clearTimeout(t); }, [load]);
  const pick = (v: string) => { setD(null); setAsking(null); setReason(""); setVer(v); };

  const run = async (f: () => Promise<unknown>, after?: () => void) => {
    setBusy(true); setErr("");
    try { await f(); after?.(); await load(); onChanged(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const tMs = moment.trim() ? parseMoment(moment) : null;
  const badMoment = moment.trim() !== "" && tMs == null;
  const v = d?.version;
  const links = v ? driveLinks(v.drive_file_id) : null;
  const roots = d?.comments.filter((c) => !c.parent_id) ?? [];

  return (
    <Sheet open onOpenChange={(o) => { if (!o) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>{d ? `${variantLabel(d.item.variant)}${d.item.style ? ` · ${d.item.style}` : ""} · v${v!.version}` : "Vídeo"}</SheetTitle>
          <SheetDescription>{d ? (d.item.guiao ? `Guião ${d.item.guiao.n} · ${d.item.guiao.tema ?? ""}` : d.item.title) : "A carregar…"}</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6">
          {err && <Alert variant="destructive"><AlertDescription>{err} <Button size="sm" variant="link" onClick={() => void load()}>Tentar de novo</Button></AlertDescription></Alert>}
          {!d && !err && <Skeleton className="aspect-[9/16] w-full max-w-xs self-center" />}
          {d && v && links && (
            <>
              <div className="flex flex-col items-center gap-2">
                <iframe key={v.drive_file_id} src={links.preview} title={d.item.title} allow="autoplay; fullscreen"
                  className="aspect-[9/16] w-full max-w-xs rounded-md border bg-black" />
                <div className="flex flex-wrap items-center justify-center gap-2 text-xs text-muted-foreground">
                  <a href={links.view} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 font-medium text-foreground underline underline-offset-2">
                    <ExternalLinkIcon className="size-3" /> Abrir na Drive
                  </a>
                  <span>Se o vídeo não abrir, pede acesso ao ficheiro na Drive.</span>
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <Badge variant={tone(v.status)}>{statusLabel(v.status)}</Badge>
                {v.decided_by && v.decided_at && <span className="text-xs text-muted-foreground">por {v.decided_by}, {when(v.decided_at)}</span>}
                {d.versions.length > 1 && (
                  <select aria-label="Versão" className="ml-auto h-8 rounded-md border bg-background px-2 text-sm" value={v.id} onChange={(e) => pick(e.target.value)}>
                    {d.versions.map((x) => <option key={x.id} value={x.id}>v{x.version} · {statusLabel(x.status)}</option>)}
                  </select>
                )}
              </div>

              {d.can.decide && v.current && v.status !== "approved" && (
                <div className="flex flex-col gap-2 rounded-md border p-3">
                  {!asking ? (
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" disabled={busy} onClick={() => void run(() => decideReview(access, v.id, "approved"))}><CheckIcon /> Aprovar</Button>
                      <Button size="sm" variant="outline" disabled={busy} onClick={() => setAsking("changes_requested")}>Pedir alterações</Button>
                      <Button size="sm" variant="ghost" disabled={busy} onClick={() => setAsking("rejected")}>Rejeitar</Button>
                    </div>
                  ) : (
                    <>
                      <label className="text-sm font-medium" htmlFor="motivo">{asking === "rejected" ? "Porque rejeitas?" : "O que tem de mudar?"}</label>
                      <Textarea id="motivo" value={reason} maxLength={2000} onChange={(e) => setReason(e.target.value)} placeholder="Ex.: aos 0:23 o corte salta; troca o take." />
                      <div className="flex gap-2">
                        <Button size="sm" variant={asking === "rejected" ? "destructive" : "default"} disabled={busy || !reason.trim()}
                          onClick={() => void run(() => decideReview(access, v.id, asking, reason.trim()), () => { setAsking(null); setReason(""); })}>
                          {asking === "rejected" ? "Rejeitar" : "Pedir alterações"}
                        </Button>
                        <Button size="sm" variant="ghost" disabled={busy} onClick={() => { setAsking(null); setReason(""); }}>Cancelar</Button>
                      </div>
                    </>
                  )}
                </div>
              )}
              {!v.current && <Alert><AlertDescription>Esta é uma versão antiga. As decisões fazem-se na mais recente.</AlertDescription></Alert>}

              <section className="flex flex-col gap-2" aria-label="Comentários">
                <h3 className="text-sm font-semibold">Comentários</h3>
                {roots.length === 0 && <p className="text-sm text-muted-foreground">Ainda sem comentários.</p>}
                {roots.map((c) => (
                  <div key={c.id} className={`flex flex-col gap-1 rounded-md border p-2 text-sm ${c.resolved_at ? "opacity-60" : ""}`}>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                      {c.t_ms != null && (
                        <a href={driveLinks(v.drive_file_id, c.t_ms).view} target="_blank" rel="noopener noreferrer"
                          className="rounded bg-muted px-1.5 py-0.5 font-mono font-medium text-foreground tabular-nums hover:underline" title="Abrir na Drive neste momento">
                          {fmtMoment(c.t_ms)}
                        </a>
                      )}
                      <span>{c.author}</span><span>{when(c.at)}</span>
                      {c.resolved_at && <span>resolvido{c.resolved_by ? ` por ${c.resolved_by}` : ""}</span>}
                      {(d.can.decide || (d.me && c.author_id === d.me)) && (
                        <Button size="xs" variant="ghost" className="ml-auto" disabled={busy}
                          onClick={() => void run(() => resolveReviewComment(access, c.id, !c.resolved_at))}>
                          {c.resolved_at ? <><Undo2Icon /> Reabrir</> : <><CheckIcon /> Resolver</>}
                        </Button>
                      )}
                    </div>
                    <p className="whitespace-pre-wrap">{c.body}</p>
                    {d.comments.filter((r) => r.parent_id === c.id).map((r) => (
                      <div key={r.id} className="ml-3 border-l pl-2 text-sm">
                        <span className="text-xs text-muted-foreground">{r.author} · {when(r.at)}</span>
                        <p className="whitespace-pre-wrap">{r.body}</p>
                      </div>
                    ))}
                  </div>
                ))}
                {d.can.comment && (
                  <form className="flex flex-col gap-2 rounded-md border p-2" onSubmit={(e) => {
                    e.preventDefault();
                    if (!body.trim() || badMoment) return;
                    void run(() => addReviewComment(access, v.id, body.trim(), tMs), () => { setBody(""); setMoment(""); });
                  }}>
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-muted-foreground" htmlFor="momento">Momento</label>
                      <Input id="momento" className="h-8 w-24 font-mono" placeholder="0:23" value={moment} onChange={(e) => setMoment(e.target.value)} aria-invalid={badMoment} />
                      <span className="text-xs text-muted-foreground">{badMoment ? "Escreve como 0:23." : "Opcional. Vê o tempo no player da Drive."}</span>
                    </div>
                    <Textarea aria-label="Comentário" value={body} maxLength={4000} onChange={(e) => setBody(e.target.value)} placeholder="O que viste neste momento?" />
                    <Button type="submit" size="sm" className="self-end" disabled={busy || !body.trim() || badMoment}>Comentar</Button>
                  </form>
                )}
              </section>

              {d.decisions.length > 0 && (
                <section className="flex flex-col gap-1" aria-label="Histórico de decisões">
                  <h3 className="text-sm font-semibold">Histórico</h3>
                  {d.decisions.map((x, i) => (
                    <p key={i} className="text-xs text-muted-foreground">
                      {when(x.at)} · {x.by}: {statusLabel(x.to)}{x.reason ? `: “${x.reason}”` : ""}
                    </p>
                  ))}
                </section>
              )}
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
