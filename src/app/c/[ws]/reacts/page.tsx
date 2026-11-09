"use client";

import { useCallback, useEffect, useState } from "react";
import { CheckIcon, DownloadIcon, ExternalLinkIcon, Loader2Icon, MicIcon, PauseIcon, PlayIcon, PlusIcon, RotateCwIcon, StarIcon, UndoIcon, XIcon, BookmarkIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WsLink } from "@/components/ws-link";
import { useFlags } from "@/lib/flags";
import type { Access } from "@/lib/access";
import {
  addReactSource, decideReact, decideReactSource, fetchReactSources, fetchReacts, reactVideoUrl, recordReact,
  type ReactItem, type ReactList, type ReactSource, type ReactTab,
} from "@/lib/reacts";
import { guiaoHref, PART_LABELS, perMille, reasonLabel, REJECT_REASONS, scoreTone, timeLeft, typeLabel, urgent } from "@/lib/reacts-format";
import { cn } from "@/lib/utils";

const nf = new Intl.NumberFormat("pt-PT", { notation: "compact", maximumFractionDigits: 1 });
const fmtWhen = (iso: string | null) => (iso ? new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");

export default function ReactsPage() {
  return <WorkspaceGate need="reacts.read">{(access) => <Reacts access={access} />}</WorkspaceGate>;
}

type View = ReactTab | "fontes";
const TABS: { v: View; label: string }[] = [
  { v: "open", label: "A decidir" }, { v: "saved", label: "Guardados" }, { v: "recorded", label: "Gravados" },
  { v: "rejected", label: "Rejeitados" }, { v: "expired", label: "Expirados" }, { v: "fontes", label: "Fontes" },
];

function Reacts({ access }: { access: Access }) {
  const flags = useFlags(access.ws, access.token);
  const [view, setView] = useState<View>("open");
  const [counts, setCounts] = useState<ReactList["counts"] | null>(null);
  if (flags && !flags.has("reacts.radar")) {
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">Reacts</h1>
        <Alert><AlertDescription>O radar de reacts ainda não está ligado para este cliente. Quem gere as funcionalidades pode ligá-lo em Definições.</AlertDescription></Alert>
      </div>
    );
  }
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Reacts</h1>
        <p className="text-sm text-muted-foreground">
          Takes polémicos para o cliente reagir, encontrados e avaliados pelo agente. Vê o vídeo, descarrega-o e decide: gravar, guardar ou rejeitar. As vossas decisões ensinam o agente.
        </p>
      </div>
      <ToggleGroup value={[view]} onValueChange={(v) => { const x = (v as string[])[0] as View | undefined; if (x) setView(x); }} variant="outline" size="sm" className="flex-wrap">
        {TABS.map((t) => (
          <ToggleGroupItem key={t.v} value={t.v}>
            {t.label}{t.v !== "fontes" && counts ? <span className="ml-1 tabular-nums text-muted-foreground">{counts[t.v as ReactTab] ?? 0}</span> : null}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
      {view === "fontes" ? <Sources access={access} /> : <Queue key={view} access={access} tab={view} onCounts={setCounts} />}
    </div>
  );
}

function Queue({ access, tab, onCounts }: { access: Access; tab: ReactTab; onCounts: (c: ReactList["counts"]) => void }) {
  const [data, setData] = useState<ReactList | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [rejecting, setRejecting] = useState<ReactItem | null>(null);
  const [rev, setRev] = useState(0);
  const load = useCallback(() => { setLoading(true); setError(""); setRev((n) => n + 1); }, []);
  useEffect(() => {
    let alive = true;
    fetchReacts(access, tab)
      .then((d) => { if (alive) { setData(d); setError(""); onCounts(d.counts); } })
      .catch((e: Error) => { if (alive) setError(e.message); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [access, tab, onCounts, rev]);

  const replace = (it: ReactItem) => {
    setData((d) => (d ? { ...d, items: it.status === tab || (tab === "open" && it.status === "open") ? d.items.map((x) => (x.id === it.id ? it : x)) : d.items.filter((x) => x.id !== it.id) } : d));
  };

  if (loading && !data) {
    return <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar reacts">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-48 w-full" />)}</div>;
  }
  if (error) {
    return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{error}</span><Button size="sm" variant="outline" onClick={load}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  }
  if (!data) return null;
  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-muted-foreground">
        {data.last_run ? <>Última recolha do agente: {fmtWhen(data.last_run)}.</> : <>O agente ainda não correu para este cliente.</>}
        {tab === "open" && " Ordenado pela nota da IA e pelo tempo que falta."}
      </p>
      {data.items.length === 0 && <Empty tab={tab} />}
      {data.items.map((it) => (
        <ReactCard key={it.id} access={access} it={it} can={data.can} onChange={replace} onReject={() => setRejecting(it)} onError={setError} />
      ))}
      <RejectDialog access={access} item={rejecting} onClose={() => setRejecting(null)} onDone={(it) => { setRejecting(null); replace(it); load(); }} />
    </div>
  );
}

function Empty({ tab }: { tab: ReactTab }) {
  const msg: Record<ReactTab, string> = {
    open: "Não há takes por decidir. O agente corre todos os dias de manhã; acrescenta contas em Fontes para alargar a pesquisa.",
    saved: "Nada guardado. Usa Guardar nos takes que queres gravar mais tarde.",
    recorded: "Ainda nenhum react passou a guião.",
    rejected: "Nenhum take rejeitado.",
    expired: "Nenhum take expirou sem decisão.",
  };
  return <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">{msg[tab]}</CardContent></Card>;
}

function ScoreBadge({ score }: { score: number | null }) {
  const tone = scoreTone(score);
  return (
    <span className={cn("inline-flex items-center rounded-md px-2 py-0.5 text-sm font-semibold tabular-nums",
      tone === "alta" && "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
      tone === "media" && "bg-amber-500/15 text-amber-700 dark:text-amber-400",
      tone === "baixa" && "bg-muted text-muted-foreground", tone === "sem" && "bg-muted text-muted-foreground")}
      title="Nota da IA: vale a pena reagir?">
      {score == null ? "sem nota" : `${score}/100`}
    </span>
  );
}

function ReactCard({ access, it, can, onChange, onReject, onError }: {
  access: Access; it: ReactItem; can: ReactList["can"]; onChange: (it: ReactItem) => void; onReject: () => void; onError: (m: string) => void;
}) {
  const [busy, setBusy] = useState<string>("");
  const [play, setPlay] = useState(false);
  const [more, setMore] = useState(false);
  const [recorded, setRecorded] = useState<string | null>(it.content_id);
  const ai = it.ai ?? {};
  const m = it.metrics ?? {};
  const act = async (name: string, f: () => Promise<ReactItem>) => {
    setBusy(name);
    try { onChange(await f()); } catch (e) { onError((e as Error).message); } finally { setBusy(""); }
  };
  const record = async () => {
    setBusy("record");
    try { const r = await recordReact(access, it.id); setRecorded(r.content_id); onChange(r.item); } catch (e) { onError((e as Error).message); } finally { setBusy(""); }
  };
  const href = guiaoHref(recorded);
  return (
    <Card>
      <CardContent className="flex flex-col gap-4 p-4 md:flex-row">
        <div className="w-full shrink-0 md:w-56">
          {it.has_video ? (
            play ? (
              <video className="aspect-[9/16] w-full rounded-md bg-black object-contain" src={reactVideoUrl(access.ws, it.id)} controls autoPlay playsInline
                onError={() => { setPlay(false); onError("Não foi possível reproduzir o vídeo. O link pode ter expirado: abre o original."); }} />
            ) : (
              <button type="button" onClick={() => setPlay(true)} className="relative flex aspect-[9/16] w-full items-center justify-center overflow-hidden rounded-md bg-muted" aria-label={`Ver o vídeo de @${it.author ?? ""}`}>
                {/* eslint-disable-next-line @next/next/no-img-element -- miniatura do CDN da plataforma, sem otimização */}
                {it.thumb_url && <img src={it.thumb_url} alt="" className="absolute inset-0 h-full w-full object-cover" referrerPolicy="no-referrer" />}
                <span className="relative rounded-full bg-black/60 p-3 text-white"><PlayIcon className="size-6" /></span>
              </button>
            )
          ) : (
            <div className="flex aspect-[9/16] w-full items-center justify-center rounded-md bg-muted p-3 text-center text-xs text-muted-foreground">
              Vídeo indisponível agora. O agente renova o link na próxima corrida; podes abrir o original.
            </div>
          )}
          <div className="mt-2 flex gap-2">
            {it.has_video && <Button size="sm" variant="outline" className="flex-1" nativeButton={false} render={<a href={reactVideoUrl(access.ws, it.id, true)} download />}><DownloadIcon /> Descarregar</Button>}
            <Button size="sm" variant="ghost" nativeButton={false} render={<a href={it.url} target="_blank" rel="noreferrer noopener" />} aria-label="Abrir o original"><ExternalLinkIcon /></Button>
          </div>
        </div>

        <div className="flex min-w-0 flex-1 flex-col gap-3">
          <div className="flex flex-wrap items-center gap-2">
            <ScoreBadge score={it.score} />
            <a href={`https://www.${it.platform === "tiktok" ? "tiktok.com/@" : "instagram.com/"}${it.author ?? ""}`} target="_blank" rel="noreferrer noopener" className="font-medium hover:underline">@{it.author ?? "?"}</a>
            <span className="text-xs text-muted-foreground">publicado {fmtWhen(it.posted_at)}</span>
            {it.status === "open" && (
              <Badge variant={urgent(it.expires_at) ? "destructive" : "outline"}>{timeLeft(it.expires_at)}</Badge>
            )}
            <Badge variant="secondary">{typeLabel(it.video_type)}</Badge>
            {it.risk_level === "alto" && <Badge variant="destructive">Risco alto</Badge>}
            {it.risk_level === "medio" && <Badge variant="outline">Risco médio</Badge>}
          </div>

          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
            {m.views != null && <span><b className="text-foreground tabular-nums">{nf.format(m.views)}</b> views</span>}
            {m.comments != null && <span><b className="text-foreground tabular-nums">{nf.format(m.comments)}</b> comentários</span>}
            <span><b className="text-foreground tabular-nums">{perMille(m.comments, m.views)}</b> coment. por mil</span>
            {m.polemic_index != null && <span title="Comentários por mil a dividir pela mediana da própria conta"><b className="text-foreground tabular-nums">{m.polemic_index.toFixed(1).replace(".", ",")}×</b> polémica face ao normal da conta</span>}
            {m.collected_at && <span title="Números públicos recolhidos pelo agente">recolhido {fmtWhen(m.collected_at)}</span>}
          </div>

          {ai.resumo && <p className="text-sm"><span className="font-medium">O take: </span>{ai.resumo}</p>}
          {ai.angulo && <p className="text-sm"><span className="font-medium">Ângulo para nós: </span>{ai.angulo}</p>}
          {ai.hooks && ai.hooks.length > 0 && (
            <ul className="flex flex-col gap-1 text-sm">
              {ai.hooks.slice(0, 3).map((h, i) => <li key={i} className="rounded-md bg-muted/60 px-2 py-1">“{h.text}”</li>)}
            </ul>
          )}
          {ai.risk_flags && ai.risk_flags.length > 0 && (
            <p className="text-xs text-destructive">Atenção: {ai.risk_flags.join(" · ")}</p>
          )}

          {more && (
            <div className="flex flex-col gap-3 rounded-md border p-3 text-sm">
              {ai.parts && (
                <div className="grid gap-1.5 sm:grid-cols-2">
                  {Object.entries(ai.parts).map(([k, v]) => (
                    <div key={k} className="flex items-center gap-2 text-xs">
                      <span className="w-40 shrink-0 text-muted-foreground">{PART_LABELS[k] ?? k}</span>
                      <span className="h-1.5 flex-1 overflow-hidden rounded bg-muted"><span className="block h-full bg-primary" style={{ width: `${Math.max(0, Math.min(100, Number(v) || 0))}%` }} /></span>
                      <span className="w-8 text-right tabular-nums">{v}</span>
                    </div>
                  ))}
                </div>
              )}
              {ai.porque && <p><span className="font-medium">Porquê: </span>{ai.porque}</p>}
              {ai.resposta && <div><p className="font-medium">Rascunho da resposta</p><p className="whitespace-pre-line text-muted-foreground">{ai.resposta}</p></div>}
              {it.caption && <div><p className="font-medium">Legenda original</p><p className="whitespace-pre-line text-muted-foreground">{it.caption}</p></div>}
              {it.transcript && <div><p className="font-medium">Transcrição</p><p className="whitespace-pre-line text-muted-foreground">{it.transcript}</p></div>}
              {ai.model && <p className="text-xs text-muted-foreground">Avaliado por {ai.model}{ai.prompt_version ? ` · ${ai.prompt_version}` : ""} · {fmtWhen(ai.evaluated_at ?? null)}</p>}
            </div>
          )}

          {it.status === "rejected" && <p className="text-xs text-muted-foreground">Rejeitado por {it.decided_label ?? "—"}: {reasonLabel(it.reject_reason)}{it.decision_note ? ` · ${it.decision_note}` : ""}</p>}

          <div className="mt-auto flex flex-wrap items-center gap-2">
            {can.record && (it.status === "open" || it.status === "saved") && !recorded && (
              <Button size="sm" onClick={record} disabled={!!busy}>{busy === "record" ? <Loader2Icon className="animate-spin" /> : <MicIcon />} Gravar</Button>
            )}
            {href && <Button size="sm" variant="outline" nativeButton={false} render={<WsLink href={href} />}><CheckIcon /> Abrir guião</Button>}
            {can.decide && it.status === "open" && (
              <Button size="sm" variant="outline" onClick={() => act("save", () => decideReact(access, it.id, "save"))} disabled={!!busy}>
                {busy === "save" ? <Loader2Icon className="animate-spin" /> : <BookmarkIcon />} Guardar
              </Button>
            )}
            {can.decide && (it.status === "open" || it.status === "saved") && (
              <Button size="sm" variant="ghost" onClick={onReject} disabled={!!busy}><XIcon /> Rejeitar</Button>
            )}
            {can.decide && (it.status === "rejected" || it.status === "saved") && (
              <Button size="sm" variant="ghost" onClick={() => act("reopen", () => decideReact(access, it.id, "reopen"))} disabled={!!busy}><UndoIcon /> Voltar à fila</Button>
            )}
            {can.decide && <Stars value={it.rating} disabled={!!busy} onPick={(n) => act("rate", () => decideReact(access, it.id, "rate", { rating: n }))} />}
            <Button size="sm" variant="link" onClick={() => setMore((v) => !v)}>{more ? "Esconder detalhe" : "Ver avaliação completa"}</Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function Stars({ value, onPick, disabled }: { value: number | null; onPick: (n: number) => void; disabled?: boolean }) {
  return (
    <div className="flex items-center" role="group" aria-label="A tua nota (ensina o agente)">
      {[1, 2, 3, 4, 5].map((n) => (
        <button key={n} type="button" disabled={disabled} onClick={() => onPick(n)} aria-label={`Nota ${n} de 5`} aria-pressed={value === n}
          className="p-0.5 text-muted-foreground hover:text-amber-500 disabled:opacity-50">
          <StarIcon className={cn("size-4", value != null && n <= value && "fill-amber-400 text-amber-500")} />
        </button>
      ))}
    </div>
  );
}

function RejectDialog({ access, item, onClose, onDone }: { access: Access; item: ReactItem | null; onClose: () => void; onDone: (it: ReactItem) => void }) {
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [forId, setForId] = useState<number | null>(null);
  if ((item?.id ?? null) !== forId) { setForId(item?.id ?? null); setReason(""); setNote(""); setError(""); }
  const submit = async () => {
    if (!item || !reason) return;
    setBusy(true); setError("");
    try { onDone(await decideReact(access, item.id, "reject", { reason, note })); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <Dialog open={!!item} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Rejeitar este take</DialogTitle>
          <DialogDescription>O motivo ensina o agente a não trazer takes parecidos.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Motivo">
          {REJECT_REASONS.map((r) => (
            <Button key={r.value} size="sm" variant={reason === r.value ? "default" : "outline"} role="radio" aria-checked={reason === r.value} onClick={() => setReason(r.value)}>{r.label}</Button>
          ))}
        </div>
        <Textarea rows={2} placeholder="Nota opcional (ex.: já reagimos a esta pessoa esta semana)" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={submit} disabled={!reason || busy}>{busy && <Loader2Icon className="animate-spin" />} Rejeitar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

const ORIGIN: Record<string, string> = {
  seed: "lista inicial", manual: "adicionada à mão", coauthor: "coautora de uma conta vigiada", tagged: "marcada num vídeo",
  related: "perfil relacionado", commenter: "comenta nas contas vigiadas", topic_search: "pesquisa por tema quente", other: "outra",
};
const SOURCE_STATUS: Record<string, string> = { proposed: "Proposta", active: "Vigiada", paused: "Em pausa", rejected: "Rejeitada" };

function Sources({ access }: { access: Access }) {
  const [data, setData] = useState<{ items: ReactSource[]; can: { manage: boolean } } | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState("");
  const [handle, setHandle] = useState("");
  const [platform, setPlatform] = useState<"instagram" | "tiktok">("instagram");
  const [rev, setRev] = useState(0);
  const load = useCallback(() => { setError(""); setRev((n) => n + 1); }, []);
  useEffect(() => {
    let alive = true;
    fetchReactSources(access).then((d) => { if (alive) setData(d); }).catch((e: Error) => { if (alive) setError(e.message); });
    return () => { alive = false; };
  }, [access, rev]);
  const act = async (key: string, f: () => Promise<ReactSource>) => {
    setBusy(key);
    try { const s = await f(); setData((d) => (d ? { ...d, items: d.items.some((x) => x.id === s.id) ? d.items.map((x) => (x.id === s.id ? s : x)) : [s, ...d.items] } : d)); }
    catch (e) { setError((e as Error).message); } finally { setBusy(""); }
  };
  if (!data && !error) return <Skeleton className="h-40 w-full" />;
  const groups: ReactSource["status"][] = ["proposed", "active", "paused", "rejected"];
  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        O agente vigia as contas ativas e procura contas parecidas (coautores, marcadas, perfis relacionados, quem comenta, temas do dia). As propostas só passam a ser vigiadas depois de alguém as aceitar.
      </p>
      {error && <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{error}</span><Button size="sm" variant="outline" onClick={load}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>}
      {data?.can.manage && (
        <form className="flex flex-wrap items-center gap-2" onSubmit={(e) => { e.preventDefault(); if (handle.trim()) act("add", () => addReactSource(access, platform, handle)).then(() => setHandle("")); }}>
          <ToggleGroup value={[platform]} onValueChange={(v) => { const x = (v as string[])[0]; if (x === "instagram" || x === "tiktok") setPlatform(x); }} variant="outline" size="sm">
            <ToggleGroupItem value="instagram">Instagram</ToggleGroupItem>
            <ToggleGroupItem value="tiktok">TikTok</ToggleGroupItem>
          </ToggleGroup>
          <Input className="w-56" placeholder="@conta" value={handle} onChange={(e) => setHandle(e.target.value)} aria-label="Conta a vigiar" maxLength={41} />
          <Button size="sm" type="submit" disabled={!handle.trim() || busy === "add"}>{busy === "add" ? <Loader2Icon className="animate-spin" /> : <PlusIcon />} Vigiar conta</Button>
        </form>
      )}
      {data && data.items.length === 0 && <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">Ainda não há contas. Acrescenta a primeira acima.</CardContent></Card>}
      {data && groups.map((g) => {
        const list = data.items.filter((s) => s.status === g);
        if (list.length === 0) return null;
        return (
          <section key={g} className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">{SOURCE_STATUS[g]} <span className="text-muted-foreground tabular-nums">{list.length}</span></h2>
            {list.map((s) => (
              <Card key={s.id}>
                <CardContent className="flex flex-wrap items-center gap-3 p-3">
                  <a href={`https://www.${s.platform === "tiktok" ? "tiktok.com/@" : "instagram.com/"}${s.handle}`} target="_blank" rel="noreferrer noopener" className="font-medium hover:underline">@{s.handle}</a>
                  <Badge variant="secondary">{s.platform === "tiktok" ? "TikTok" : "Instagram"}</Badge>
                  {s.score != null && <ScoreBadge score={Math.round(Number(s.score))} />}
                  <span className="text-xs text-muted-foreground">{ORIGIN[s.origin] ?? s.origin}{s.origin_detail ? ` · ${s.origin_detail}` : ""}</span>
                  <span className="text-xs text-muted-foreground tabular-nums">{s.candidates} takes</span>
                  {data.can.manage && (
                    <div className="ml-auto flex gap-2">
                      {s.status === "proposed" && <>
                        <Button size="sm" onClick={() => act(s.id, () => decideReactSource(access, s.id, "accept"))} disabled={busy === s.id}><CheckIcon /> Vigiar</Button>
                        <Button size="sm" variant="ghost" onClick={() => act(s.id, () => decideReactSource(access, s.id, "reject"))} disabled={busy === s.id}><XIcon /> Rejeitar</Button>
                      </>}
                      {s.status === "active" && <Button size="sm" variant="ghost" onClick={() => act(s.id, () => decideReactSource(access, s.id, "pause"))} disabled={busy === s.id}><PauseIcon /> Pausar</Button>}
                      {(s.status === "paused" || s.status === "rejected") && <Button size="sm" variant="outline" onClick={() => act(s.id, () => decideReactSource(access, s.id, "resume"))} disabled={busy === s.id}><PlayIcon /> Vigiar</Button>}
                    </div>
                  )}
                </CardContent>
              </Card>
            ))}
          </section>
        );
      })}
    </div>
  );
}
