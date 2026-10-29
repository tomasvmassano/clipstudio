"use client";

import { wsPath } from "@/lib/ws-path";
import { WsLink } from "@/components/ws-link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import {
  CheckIcon, ExternalLinkIcon, FilePlus2Icon, InboxIcon, Loader2Icon, MegaphoneIcon, PlusIcon, RotateCwIcon, SearchIcon, UndoIcon, XIcon,
} from "lucide-react";
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
import { todayDubai } from "@/lib/data";
import { createRequest, createSource, duplicateOf, fetchSources, sourceToScript, updateSource } from "@/lib/sources";
import { EDITORIAL_LABEL, SOURCE_STATUS_LABEL, type Source } from "@/lib/types";

type Tab = "entrada" | "selecionadas" | "pedidos" | "usadas" | "descartadas" | "todas";
const ORIGEM: Record<string, string> = { reporter: "Repórter", curious: "Curioso", philosopher: "Filósofo", manual: "Manual", talento: "Talento" };
const TIPOS = ["noticia", "artigo", "livro", "reel", "video", "podcast", "comentario", "outro"];

export default function FontesPage() {
  const q = useSearchParams().get("q") ?? "";
  return <WorkspaceGate need="sources.read">{(access) => <Fontes key={q} access={access} />}</WorkspaceGate>;
}

function Fontes({ access }: { access: Access }) {
  const { can } = useSession();
  const caps = { create: can("sources.create"), triage: can("sources.triage"), request: can("requests.create"), script: can("scripts.create") };
  const [all, setAll] = useState<Source[] | null>(null);
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  // ?q= vem da pesquisa global (FR-16-01): abre a lista já filtrada
  const initialQ = (useSearchParams().get("q") ?? "").slice(0, 100);
  const [q, setQ] = useState(initialQ); const [query, setQuery] = useState(initialQ);
  const [tab, setTab] = useState<Tab>(initialQ ? "todas" : "entrada");
  const [rev, setRev] = useState(0);
  const [adding, setAdding] = useState(false);
  const [asking, setAsking] = useState(false);
  const [highlight, setHighlight] = useState<number | null>(null);

  useEffect(() => {
    let alive = true;
    fetchSources(access, { q: query }, 300)
      .then((x) => { if (alive) { setAll(x); setErr(""); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, query, rev]);

  const put = useCallback((s: Source) => setAll((prev) => (prev ? (prev.some((x) => x.id === s.id) ? prev.map((x) => (x.id === s.id ? s : x)) : [s, ...prev]) : [s])), []);

  const today = new Date().toISOString().slice(0, 10);
  const expired = (s: Source) => !!s.expira_em && s.expira_em < today;
  const dead = (s: Source) => s.status === "descartada" || s.status === "rejeitada";
  const shown = useMemo(() => (all ?? []).filter((s) => {
    if (tab === "entrada") return s.kind === "source" && (s.status === "nova" || s.status === "triagem") && !expired(s);
    if (tab === "selecionadas") return s.status === "selecionada";
    if (tab === "pedidos") return s.kind === "talent_request" && !dead(s);
    if (tab === "usadas") return s.status === "usada";
    if (tab === "descartadas") return dead(s);
    return true;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [all, tab]);
  const count = (t: Tab) => (all ?? []).filter((s) => {
    if (t === "entrada") return s.kind === "source" && (s.status === "nova" || s.status === "triagem") && !expired(s);
    if (t === "pedidos") return s.kind === "talent_request" && !dead(s) && s.status !== "usada";
    return false;
  }).length;

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Fontes</h1>
          <p className="text-sm text-muted-foreground">
            O que os agentes trouxeram, o que a equipa juntou e os pedidos do talento. Triar, transformar em guião e manter a origem de cada ideia.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {caps.request && <Button size="sm" variant="outline" onClick={() => setAsking(true)}><MegaphoneIcon /> Pedir um tema</Button>}
          {caps.create && <Button size="sm" onClick={() => setAdding(true)}><PlusIcon /> Adicionar fonte</Button>}
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <ToggleGroup value={[tab]} onValueChange={(v) => setTab(((v as string[])[0] as Tab) ?? "entrada")} variant="outline" size="sm">
          <ToggleGroupItem value="entrada"><InboxIcon /> Por triar {count("entrada") > 0 && <span className="tabular-nums">({count("entrada")})</span>}</ToggleGroupItem>
          <ToggleGroupItem value="selecionadas">Selecionadas</ToggleGroupItem>
          <ToggleGroupItem value="pedidos">Pedidos {count("pedidos") > 0 && <span className="tabular-nums">({count("pedidos")})</span>}</ToggleGroupItem>
          <ToggleGroupItem value="usadas">Usadas</ToggleGroupItem>
          <ToggleGroupItem value="descartadas">Descartadas</ToggleGroupItem>
          <ToggleGroupItem value="todas">Todas</ToggleGroupItem>
        </ToggleGroup>
        <form className="ml-auto flex items-center gap-2" onSubmit={(e) => { e.preventDefault(); setQuery(q); }}>
          <Input aria-label="Pesquisar fontes" className="h-8 w-56" placeholder="Pesquisar título, take, tag…" value={q} onChange={(e) => setQ(e.target.value)} />
          <Button size="sm" variant="outline" type="submit" aria-label="Pesquisar"><SearchIcon /></Button>
        </form>
      </div>

      {(err || msg) && (
        <Alert variant="destructive">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>{err || msg}</span>
            {err && <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button>}
            {msg && <Button size="sm" variant="ghost" onClick={() => setMsg("")}>Fechar</Button>}
          </AlertDescription>
        </Alert>
      )}

      {!all ? (
        !err && <div className="grid gap-3 md:grid-cols-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-36" />)}</div>
      ) : shown.length === 0 ? (
        <Alert><AlertDescription>{emptyText(tab, !!query)}</AlertDescription></Alert>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {shown.map((s) => (
            <SourceCard key={s.id} s={s} access={access} caps={caps} expired={expired(s)} highlight={highlight === s.id} onChange={put} onError={setMsg} />
          ))}
        </div>
      )}

      <AddSourceDialog open={adding} onOpenChange={setAdding} access={access}
        onDone={(s) => { put(s); setTab("entrada"); setHighlight(s.id); }}
        onDuplicate={(id) => { setAdding(false); setTab("todas"); setHighlight(id); setMsg("Essa fonte já existia: está destacada na lista."); }} />
      <RequestDialog open={asking} onOpenChange={setAsking} access={access} onDone={(s) => { put(s); setTab("pedidos"); setHighlight(s.id); }} />
    </div>
  );
}

function emptyText(tab: Tab, searching: boolean) {
  if (searching) return "Nada encontrado com essa pesquisa.";
  if (tab === "entrada") return "Nada por triar. As fontes novas dos agentes aparecem aqui depois da corrida diária.";
  if (tab === "pedidos") return "Ainda não há pedidos do talento.";
  return "Nada aqui por agora.";
}

function SourceCard({ s, access, caps, expired, highlight, onChange, onError }: {
  s: Source; access: Access; caps: { triage: boolean; script: boolean }; expired: boolean; highlight: boolean;
  onChange: (s: Source) => void; onError: (m: string) => void;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  const [reason, setReason] = useState("");
  const dead = s.status === "descartada" || s.status === "rejeitada";
  const req = s.kind === "talent_request";

  const run = async (fn: () => Promise<Source>) => {
    setBusy(true);
    try { onChange(await fn()); setDiscarding(false); setReason(""); }
    catch (e) { onError((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <Card data-fonte={s.id} className={(dead || expired ? "opacity-60 " : "") + (highlight ? "ring-2 ring-primary" : "")}>
      <CardContent className="flex flex-col gap-2 p-4">
        <div className="flex flex-wrap items-center gap-1.5 text-xs">
          {req ? <Badge className="bg-amber-500 text-black">pedido do talento</Badge> : <Badge variant="outline">{s.fonte_tipo ?? "fonte"}</Badge>}
          <Badge variant={s.status === "selecionada" ? "default" : "outline"}>{SOURCE_STATUS_LABEL[s.status]}</Badge>
          {s.categoria && <Badge variant="secondary">{s.categoria}</Badge>}
          {expired && <Badge variant="destructive">expirada</Badge>}
          <span className="ml-auto text-muted-foreground">
            {ORIGEM[s.agent ?? ""] ?? s.created_label ?? s.agent} · {new Date(s.created_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}
          </span>
        </div>
        <div className="font-semibold">{s.titulo}</div>
        {s.take && <p className="text-sm">{s.take}</p>}
        {s.resumo && !req && <p className="line-clamp-3 text-sm text-muted-foreground">{s.resumo}</p>}
        {req && s.resumo && s.resumo !== s.titulo && <p className="whitespace-pre-line text-sm text-muted-foreground">{s.resumo}</p>}
        {s.fonte_url && (
          <a href={s.fonte_url} target="_blank" rel="noopener" className="inline-flex items-center gap-1 truncate text-xs underline underline-offset-2">
            {s.fonte ? `${s.fonte} · ` : ""}{s.fonte_url.replace(/^https?:\/\/(www\.)?/, "").slice(0, 60)} <ExternalLinkIcon className="size-3" />
          </a>
        )}
        {!s.fonte_url && s.fonte && <p className="text-xs text-muted-foreground">{s.fonte}</p>}
        {s.tags.length > 0 && <div className="flex flex-wrap gap-1">{s.tags.map((t) => <Badge key={t} variant="secondary" className="text-[10px]">#{t}</Badge>)}</div>}
        {dead && s.status_reason && <p className="text-xs text-destructive">Motivo: {s.status_reason}</p>}
        {s.linked.length > 0 && (
          <div className="flex flex-wrap items-center gap-1 text-xs text-muted-foreground">
            Usada em:
            {s.linked.map((g) => (
              <WsLink key={g.id} href={`/guioes?date=${g.date}`} className="rounded border px-1.5 py-0.5 hover:bg-muted">
                {g.date.slice(5)} #{g.n} · {EDITORIAL_LABEL[g.editorial_status]}
              </WsLink>
            ))}
          </div>
        )}

        {discarding ? (
          <form className="flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); run(() => updateSource(access, s.id, { status: "descartada", status_reason: reason })); }}>
            <Input aria-label="Motivo para descartar" className="min-w-[12rem] flex-1" autoFocus required value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Porque não serve?" />
            <Button size="sm" variant="destructive" type="submit" disabled={busy || !reason.trim()}>Descartar</Button>
            <Button size="sm" variant="ghost" type="button" onClick={() => setDiscarding(false)}>Cancelar</Button>
          </form>
        ) : (
          <div className="flex flex-wrap gap-1.5 pt-1">
            {caps.script && !dead && (
              <Button size="sm" disabled={busy} onClick={async () => {
                setBusy(true);
                try { await sourceToScript(access, s.id, todayDubai()); router.push(wsPath(`/guioes?date=${todayDubai()}`)); }
                catch (e) { onError((e as Error).message); setBusy(false); }
              }}>
                {busy ? <Loader2Icon className="animate-spin" /> : <FilePlus2Icon />} Criar guião
              </Button>
            )}
            {caps.triage && !dead && s.status !== "selecionada" && s.status !== "usada" && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => updateSource(access, s.id, { status: "selecionada" }))}><CheckIcon /> Selecionar</Button>
            )}
            {caps.triage && s.status === "nova" && !req && (
              <Button size="sm" variant="ghost" disabled={busy} onClick={() => run(() => updateSource(access, s.id, { status: "triagem" }))}>Em triagem</Button>
            )}
            {caps.triage && !dead && s.status !== "usada" && (
              <Button size="sm" variant="ghost" disabled={busy} onClick={() => setDiscarding(true)}><XIcon /> Descartar</Button>
            )}
            {caps.triage && (dead || s.status === "selecionada") && (
              <Button size="sm" variant="ghost" disabled={busy} onClick={() => run(() => updateSource(access, s.id, { status: "nova" }))}><UndoIcon /> Voltar a nova</Button>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function AddSourceDialog({ open, onOpenChange, access, onDone, onDuplicate }: {
  open: boolean; onOpenChange: (v: boolean) => void; access: Access; onDone: (s: Source) => void; onDuplicate: (id: number) => void;
}) {
  const empty = { titulo: "", fonte_url: "", fonte: "", fonte_tipo: "noticia", categoria: "", resumo: "", tags: "" };
  const [f, setF] = useState(empty);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const set = (k: keyof typeof empty) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => setF({ ...f, [k]: e.target.value });
  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) { setErr(""); } }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Adicionar fonte</DialogTitle>
          <DialogDescription>Fica guardado quem a trouxe e quando. Se o link já existir neste cliente, mostro a que já lá está.</DialogDescription>
        </DialogHeader>
        <form
          className="flex flex-col gap-3"
          onSubmit={async (e) => {
            e.preventDefault(); setBusy(true); setErr("");
            try {
              const s = await createSource(access, {
                titulo: f.titulo, fonte_url: f.fonte_url, fonte: f.fonte, fonte_tipo: f.fonte_tipo, categoria: f.categoria, resumo: f.resumo,
                tags: f.tags.split(",").map((t) => t.trim()).filter(Boolean),
              });
              onDone(s); setF(empty); onOpenChange(false);
            } catch (er) {
              const d = duplicateOf(er);
              if (d) onDuplicate(d); else setErr((er as Error).message);
            } finally { setBusy(false); }
          }}
        >
          <label className="flex flex-col gap-1 text-sm">Título<Input required value={f.titulo} onChange={set("titulo")} /></label>
          <label className="flex flex-col gap-1 text-sm">Link<Input type="url" placeholder="https://" value={f.fonte_url} onChange={set("fonte_url")} /></label>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1 text-sm">Origem<Input placeholder="ex.: Público, RTP" value={f.fonte} onChange={set("fonte")} /></label>
            <label className="flex flex-col gap-1 text-sm">Tipo
              <select className="h-9 rounded-md border bg-background px-2 text-sm" value={f.fonte_tipo} onChange={set("fonte_tipo")}>
                {TIPOS.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </label>
          </div>
          <label className="flex flex-col gap-1 text-sm">Resumo<Textarea rows={3} value={f.resumo} onChange={set("resumo")} /></label>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-1 text-sm">Categoria<Input value={f.categoria} onChange={set("categoria")} /></label>
            <label className="flex flex-col gap-1 text-sm">Tags<Input placeholder="separadas por vírgula" value={f.tags} onChange={set("tags")} /></label>
          </div>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter>
            <Button type="submit" disabled={busy || !f.titulo.trim()}>{busy && <Loader2Icon className="animate-spin" />} Guardar fonte</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function RequestDialog({ open, onOpenChange, access, onDone }: { open: boolean; onOpenChange: (v: boolean) => void; access: Access; onDone: (s: Source) => void }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) setErr(""); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Pedir um tema</DialogTitle>
          <DialogDescription>Diz o que te apetece gravar ou o que viste. O pedido entra nas fontes e a equipa decide se vira guião; nada é gerado nem publicado sem aprovação.</DialogDescription>
        </DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          try { onDone(await createRequest(access, text)); setText(""); onOpenChange(false); }
          catch (er) { setErr((er as Error).message); }
          finally { setBusy(false); }
        }}>
          <Textarea aria-label="O teu pedido" rows={5} maxLength={2000} autoFocus value={text} onChange={(e) => setText(e.target.value)}
            placeholder="Ex.: quero falar do preço das casas no Algarve, vi um anúncio absurdo hoje." />
          <p className="text-right text-xs text-muted-foreground tabular-nums">{text.length}/2000</p>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter><Button type="submit" disabled={busy || text.trim().length < 3}>{busy && <Loader2Icon className="animate-spin" />} Enviar pedido</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
