"use client";

import { WsLink } from "@/components/ws-link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { ArchiveIcon, BookmarkPlusIcon, ExternalLinkIcon, Loader2Icon, PencilIcon, PlusIcon, RotateCwIcon, SearchIcon, StarIcon, UndoIcon } from "lucide-react";
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
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { createReference, fetchDiscover, fetchReferences, updateReference } from "@/lib/references";
import type { Discover, DiscoverReel, RefMetrics, Reference } from "@/lib/types";
import { cn } from "@/lib/utils";

const nf = new Intl.NumberFormat("pt-PT", { notation: "compact", maximumFractionDigits: 1 });
const fmtDay = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" }) : "");

export default function ReferenciasPage() {
  const q = useSearchParams().get("q") ?? "";
  return <WorkspaceGate need="references.read">{(access) => <Referencias key={q} access={access} />}</WorkspaceGate>;
}

type Tab = "biblioteca" | "descobrir" | "arquivo";

function Referencias({ access }: { access: Access }) {
  const { can } = useSession();
  const manage = can("references.manage");
  const [tab, setTab] = useState<Tab>("biblioteca");
  const [msg, setMsg] = useState("");
  const [adding, setAdding] = useState(false);
  const [rev, setRev] = useState(0);

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Referências</h1>
          <p className="text-sm text-muted-foreground">
            Biblioteca de inspiração deste cliente: o que guardámos, como está classificado e em que guiões já serviu. Os números vêm do scraper, com a data de recolha.
          </p>
        </div>
        {manage && <Button size="sm" onClick={() => setAdding(true)}><PlusIcon /> Adicionar por link</Button>}
      </div>
      <ToggleGroup value={[tab]} onValueChange={(v) => setTab(((v as string[])[0] as Tab) ?? "biblioteca")} variant="outline" size="sm">
        <ToggleGroupItem value="biblioteca">Biblioteca</ToggleGroupItem>
        <ToggleGroupItem value="descobrir">Descobrir</ToggleGroupItem>
        {manage && <ToggleGroupItem value="arquivo">Arquivo</ToggleGroupItem>}
      </ToggleGroup>
      {msg && (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{msg}</span><Button size="sm" variant="ghost" onClick={() => setMsg("")}>Fechar</Button></AlertDescription></Alert>
      )}
      {tab === "descobrir"
        ? <DiscoverView access={access} manage={manage} onError={setMsg} onSaved={() => setRev((n) => n + 1)} />
        : <Library key={`${tab}-${rev}`} access={access} manage={manage} archived={tab === "arquivo"} onError={setMsg} />}
      <AddDialog open={adding} onOpenChange={setAdding} access={access} onDone={() => { setTab("biblioteca"); setRev((n) => n + 1); }} />
    </div>
  );
}

function Metrics({ m }: { m: RefMetrics | null }) {
  if (!m) return null;
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
      {m.views != null && <span><b className="text-foreground tabular-nums">{nf.format(m.views)}</b> views</span>}
      {m.outlier != null && <span><b className="text-foreground tabular-nums">{m.outlier.toFixed(1)}×</b> a mediana do criador</span>}
      {m.comments != null && <span className="tabular-nums">{nf.format(m.comments)} comentários</span>}
      <span title="Números recolhidos pelo scraper; não são da API oficial">scraper · {fmtDay(m.collected_at)}</span>
    </div>
  );
}

function Library({ access, manage, archived, onError }: { access: Access; manage: boolean; archived: boolean; onError: (m: string) => void }) {
  const [items, setItems] = useState<Reference[] | null>(null);
  const [err, setErr] = useState("");
  // ?q= vem da pesquisa global (FR-16-01): abre a lista já filtrada
  const initialQ = (useSearchParams().get("q") ?? "").slice(0, 100);
  const [q, setQ] = useState(initialQ); const [query, setQuery] = useState(initialQ);
  const [colecao, setColecao] = useState(""); const [favoritos, setFavoritos] = useState(false);
  const [editing, setEditing] = useState<Reference | null>(null);
  const [allCols, setAllCols] = useState<string[]>([]);
  const [rev, setRev] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchReferences(access, { q: query, colecao, favoritos, archived })
      .then((x) => {
        if (!alive) return;
        setItems(x); setErr("");
        if (!colecao) setAllCols([...new Set(x.flatMap((i) => i.colecoes))].sort());
      })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, query, colecao, favoritos, archived, rev]);
  const put = useCallback((r: Reference) => setItems((p) => (p ?? []).map((x) => (x.id === r.id ? r : x))), []);
  const run = async (id: number, patch: Record<string, unknown>, drop = false) => {
    try { const r = await updateReference(access, id, patch); if (drop) setItems((p) => (p ?? []).filter((x) => x.id !== id)); else put(r); }
    catch (e) { onError((e as Error).message); }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <form className="flex items-center gap-2" onSubmit={(e) => { e.preventDefault(); setQuery(q); }}>
          <Input aria-label="Pesquisar referências" className="h-8 w-60" placeholder="Pesquisar título, hook, criador…" value={q} onChange={(e) => setQ(e.target.value)} />
          <Button size="sm" variant="outline" type="submit" aria-label="Pesquisar"><SearchIcon /></Button>
        </form>
        {allCols.length > 0 && (
          <select aria-label="Filtrar por coleção" className="h-8 rounded-md border bg-background px-2 text-sm" value={colecao} onChange={(e) => setColecao(e.target.value)}>
            <option value="">Todas as coleções</option>
            {allCols.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        )}
        <Button size="sm" variant={favoritos ? "default" : "outline"} aria-pressed={favoritos} onClick={() => setFavoritos(!favoritos)}><StarIcon /> Favoritos</Button>
      </div>
      {err && <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{err}</span><Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>}
      {!items ? (!err && <div className="grid gap-3 md:grid-cols-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-40" />)}</div>)
        : items.length === 0 ? (
          <Alert><AlertDescription>{archived ? "Nada arquivado." : query || colecao || favoritos ? "Nada com estes filtros." : "A biblioteca está vazia. Guarda reels em Descobrir ou adiciona um link."}</AlertDescription></Alert>
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {items.map((r) => (
              <Card key={r.id} data-ref={r.id}>
                <CardContent className="flex flex-col gap-2 p-4">
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    {r.creator && <Badge variant="outline">@{r.creator}</Badge>}
                    {r.platform && <Badge variant="secondary">{r.platform}</Badge>}
                    {r.formato && <Badge variant="secondary">{r.formato}</Badge>}
                    {r.estilo && <Badge variant="secondary">{r.estilo}</Badge>}
                    {r.duracao_s && <span className="text-muted-foreground tabular-nums">{r.duracao_s}s</span>}
                    {manage && !archived ? (
                      <Button size="icon-sm" variant="ghost" className="ml-auto" aria-pressed={r.favorito} aria-label={r.favorito ? "Tirar dos favoritos" : "Marcar favorito"} onClick={() => run(r.id, { favorito: !r.favorito })}>
                        <StarIcon className={cn(r.favorito && "fill-amber-400 text-amber-400")} />
                      </Button>
                    ) : r.favorito ? <StarIcon className="ml-auto size-4 fill-amber-400 text-amber-400" aria-label="Favorito" /> : null}
                  </div>
                  <div className="font-semibold">{r.titulo}</div>
                  {r.hook && r.hook !== r.titulo && <p className="text-sm">Hook: “{r.hook}”</p>}
                  {r.analysis?.porque_viraliza && <p className="line-clamp-3 text-sm text-muted-foreground">{r.analysis.porque_viraliza}</p>}
                  {r.notas && <p className="rounded-md bg-muted/50 px-2 py-1 text-xs">{r.notas}</p>}
                  <Metrics m={r.metrics} />
                  {(r.tags.length > 0 || r.colecoes.length > 0) && (
                    <div className="flex flex-wrap gap-1">
                      {r.colecoes.map((c) => <Badge key={`c-${c}`} className="text-[10px]">{c}</Badge>)}
                      {r.tags.map((t) => <Badge key={`t-${t}`} variant="secondary" className="text-[10px]">#{t}</Badge>)}
                    </div>
                  )}
                  {r.links.length > 0 && (
                    <div className="flex flex-wrap items-center gap-1 text-xs text-muted-foreground">
                      Usada em:
                      {r.links.map((l, i) => l.content_id
                        ? <WsLink key={i} href={`/guioes?date=${l.content_id.slice(-13, -3)}`} className="rounded border px-1.5 py-0.5 hover:bg-muted">{l.label}</WsLink>
                        : <WsLink key={i} href="/fontes" className="rounded border px-1.5 py-0.5 hover:bg-muted">fonte: {l.label}</WsLink>)}
                    </div>
                  )}
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    {r.url && <Button size="sm" variant="outline" render={<a href={r.url} target="_blank" rel="noopener" />} nativeButton={false}><ExternalLinkIcon /> Abrir original</Button>}
                    {manage && !archived && <Button size="sm" variant="ghost" onClick={() => setEditing(r)}><PencilIcon /> Classificar</Button>}
                    {manage && !archived && <Button size="sm" variant="ghost" onClick={() => run(r.id, { archived: true }, true)}><ArchiveIcon /> Arquivar</Button>}
                    {manage && archived && <Button size="sm" variant="outline" onClick={() => run(r.id, { archived: false }, true)}><UndoIcon /> Recuperar</Button>}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      {editing && <EditDialog r={editing} access={access} onClose={() => setEditing(null)} onSaved={(r) => { put(r); setEditing(null); }} />}
    </div>
  );
}

function DiscoverView({ access, manage, onError, onSaved }: { access: Access; manage: boolean; onError: (m: string) => void; onSaved: () => void }) {
  const [d, setD] = useState<Discover | null>(null);
  const [err, setErr] = useState("");
  const [account, setAccount] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [rev, setRev] = useState(0);
  useEffect(() => {
    let alive = true;
    fetchDiscover(access, account).then((x) => { if (alive) { setD(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, account, rev]);
  const creators = useMemo(() => d?.creators ?? [], [d]);
  const save = async (x: DiscoverReel) => {
    setBusy(x.id);
    try { await createReference(access, { reel_id: x.id }); setD((p) => (p ? { ...p, reels: p.reels.filter((z) => z.id !== x.id) } : p)); onSaved(); }
    catch (e) { onError((e as Error).message); }
    finally { setBusy(null); }
  };
  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">Reels dos criadores que seguimos para este cliente, do mais acima da mediana para baixo. Só aparecem os que ainda não estão na biblioteca.</p>
      {creators.length > 0 && (
        <select aria-label="Filtrar por criador" className="h-8 w-fit rounded-md border bg-background px-2 text-sm" value={account} onChange={(e) => setAccount(e.target.value)}>
          <option value="">Todos os criadores ({creators.length})</option>
          {creators.map((c) => <option key={c.id} value={c.id}>@{c.handle} · {c.reels} reels</option>)}
        </select>
      )}
      {err && <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2"><span>{err}</span><Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>}
      {!d ? (!err && <div className="grid gap-3 md:grid-cols-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-36" />)}</div>)
        : d.creators.length === 0 ? <Alert><AlertDescription>Este cliente ainda não tem criadores de referência configurados.</AlertDescription></Alert>
        : d.reels.length === 0 ? <Alert><AlertDescription>Já guardaste tudo o que havia destes criadores.</AlertDescription></Alert>
        : (
          <div className="grid gap-3 md:grid-cols-2">
            {d.reels.map((x) => (
              <Card key={x.id} data-reel={x.id}>
                <CardContent className="flex flex-col gap-2 p-4">
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    <Badge variant="outline">@{x.creator}</Badge>
                    {x.analysis?.formato && <Badge variant="secondary">{x.analysis.formato}</Badge>}
                    {x.duration ? <span className="text-muted-foreground tabular-nums">{Math.round(x.duration)}s</span> : null}
                  </div>
                  <div className="font-semibold">{x.hook ?? x.caption ?? "Sem hook transcrito"}</div>
                  {x.analysis?.porque_viraliza && <p className="line-clamp-3 text-sm text-muted-foreground">{x.analysis.porque_viraliza}</p>}
                  <Metrics m={{ views: x.views, likes: x.likes, comments: x.comments, outlier: x.outlier, duration: x.duration, collected_at: x.collected_at, source: "scraper" }} />
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    {x.url && <Button size="sm" variant="outline" render={<a href={x.url} target="_blank" rel="noopener" />} nativeButton={false}><ExternalLinkIcon /> Ver</Button>}
                    {manage && <Button size="sm" disabled={busy === x.id} onClick={() => save(x)}>{busy === x.id ? <Loader2Icon className="animate-spin" /> : <BookmarkPlusIcon />} Guardar na biblioteca</Button>}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
    </div>
  );
}

const list = (s: string) => s.split(",").map((x) => x.trim()).filter(Boolean);

function EditDialog({ r, access, onClose, onSaved }: { r: Reference; access: Access; onClose: () => void; onSaved: (r: Reference) => void }) {
  const [f, setF] = useState({
    titulo: r.titulo, hook: r.hook ?? "", formato: r.formato ?? "", estilo: r.estilo ?? "", narrativa: r.narrativa ?? "",
    duracao_s: r.duracao_s ? String(r.duracao_s) : "", idioma: r.idioma ?? "", tags: r.tags.join(", "), colecoes: r.colecoes.join(", "), notas: r.notas ?? "",
  });
  const [busy, setBusy] = useState(false); const [err, setErr] = useState("");
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="max-h-[90svh] overflow-y-auto">
        <DialogHeader><DialogTitle>Classificar referência</DialogTitle><DialogDescription>Formato, estilo, narrativa e coleções ajudam a encontrar isto quando estiveres a escrever.</DialogDescription></DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          try {
            onSaved(await updateReference(access, r.id, {
              titulo: f.titulo, hook: f.hook, formato: f.formato, estilo: f.estilo, narrativa: f.narrativa, duracao_s: f.duracao_s, idioma: f.idioma,
              tags: list(f.tags), colecoes: list(f.colecoes), notas: f.notas,
            }));
          } catch (er) { setErr((er as Error).message); } finally { setBusy(false); }
        }}>
          <label className="flex flex-col gap-1 text-sm">Título<Input required value={f.titulo} onChange={set("titulo")} /></label>
          <label className="flex flex-col gap-1 text-sm">Hook<Input value={f.hook} onChange={set("hook")} /></label>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1 text-sm">Formato<Input value={f.formato} onChange={set("formato")} /></label>
            <label className="flex flex-col gap-1 text-sm">Estilo<Input value={f.estilo} onChange={set("estilo")} placeholder="ex.: calmo, agressivo" /></label>
            <label className="flex flex-col gap-1 text-sm">Duração (s)<Input type="number" min={1} max={7200} value={f.duracao_s} onChange={set("duracao_s")} /></label>
            <label className="flex flex-col gap-1 text-sm">Idioma<Input value={f.idioma} onChange={set("idioma")} /></label>
          </div>
          <label className="flex flex-col gap-1 text-sm">Narrativa<Textarea rows={2} value={f.narrativa} onChange={set("narrativa")} /></label>
          <label className="flex flex-col gap-1 text-sm">Coleções<Input value={f.colecoes} onChange={set("colecoes")} placeholder="separadas por vírgula" /></label>
          <label className="flex flex-col gap-1 text-sm">Tags<Input value={f.tags} onChange={set("tags")} placeholder="separadas por vírgula" /></label>
          <label className="flex flex-col gap-1 text-sm">Notas<Textarea rows={2} value={f.notas} onChange={set("notas")} /></label>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter><Button type="submit" disabled={busy || !f.titulo.trim()}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function AddDialog({ open, onOpenChange, access, onDone }: { open: boolean; onOpenChange: (v: boolean) => void; access: Access; onDone: () => void }) {
  const [f, setF] = useState({ url: "", titulo: "", creator: "", formato: "", colecoes: "", notas: "" });
  const [busy, setBusy] = useState(false); const [err, setErr] = useState("");
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) setErr(""); }}>
      <DialogContent>
        <DialogHeader><DialogTitle>Adicionar referência por link</DialogTitle><DialogDescription>Guardamos o link original e a autoria. Sem números: só aparecem quando vêm do scraper.</DialogDescription></DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          try { await createReference(access, { ...f, colecoes: list(f.colecoes) }); setF({ url: "", titulo: "", creator: "", formato: "", colecoes: "", notas: "" }); onOpenChange(false); onDone(); }
          catch (er) { setErr((er as { raw?: string }).raw?.startsWith("duplicado:") ? "Esse link já está na biblioteca." : (er as Error).message); }
          finally { setBusy(false); }
        }}>
          <label className="flex flex-col gap-1 text-sm">Link<Input type="url" required placeholder="https://" value={f.url} onChange={set("url")} /></label>
          <label className="flex flex-col gap-1 text-sm">Título<Input value={f.titulo} onChange={set("titulo")} placeholder="Se ficar vazio, uso o link" /></label>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1 text-sm">Criador<Input value={f.creator} onChange={set("creator")} /></label>
            <label className="flex flex-col gap-1 text-sm">Formato<Input value={f.formato} onChange={set("formato")} /></label>
          </div>
          <label className="flex flex-col gap-1 text-sm">Coleções<Input value={f.colecoes} onChange={set("colecoes")} placeholder="separadas por vírgula" /></label>
          <label className="flex flex-col gap-1 text-sm">Notas<Textarea rows={2} value={f.notas} onChange={set("notas")} /></label>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter><Button type="submit" disabled={busy || !f.url.trim()}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
