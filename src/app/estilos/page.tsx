"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CopyIcon, PlusIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/components/session-provider";
import { StylePreview } from "@/components/edit/style-preview";
import { isRenderable } from "@/lib/style-options-client";
import {
  STATUS_LABEL, fetchAgencyLibrary, importAgencyStyle, nextStyleKey, saveAgencyStyle, setAgencyStyleStatus, specProblems,
  type AgencyLibrary, type AgencyStyle, type StyleSpec, type StyleStatus,
} from "@/lib/edit-styles";
import { cn } from "@/lib/utils";

/*
 * Biblioteca de estilos da agência (PRD REF-07, REF-08; W10-42, ADR-0084). Espaço da agência: os estilos nascem aqui, com
 * versões, e importam-se para cada cliente como uma cópia fixa. O cliente fica nessa versão até alguém carregar em
 * "Atualizar". A equipa dos clientes nunca vê esta página (o servidor recusa).
 */

const statusVariant = (s: StyleStatus) => (s === "ativo" ? "default" : s === "arquivado" ? "outline" : "secondary");
const EMPTY: StyleSpec = { canvas: { w: 1080, h: 1920 }, layers: [] };

export default function EstilosAgenciaPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("styles.library.manage")) return <Alert><AlertDescription>A biblioteca de estilos é da agência: só o dono e os administradores da agência a veem.</AlertDescription></Alert>;
  return <Library />;
}

function Library() {
  const [lib, setLib] = useState<AgencyLibrary | null>(null);
  const [err, setErr] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    try { setLib(await fetchAgencyLibrary()); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, []);
  useEffect(() => {
    let alive = true;
    fetchAgencyLibrary().then((l) => { if (alive) { setLib(l); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, []);

  const current = lib?.styles.find((s) => s.key === open) ?? null;
  const visible = (lib?.styles ?? []).filter((s) => showArchived || s.status !== "arquivado");
  const archived = (lib?.styles ?? []).filter((s) => s.status === "arquivado").length;

  const create = async (from?: AgencyStyle) => {
    if (!lib) return;
    const k = nextStyleKey(lib.styles.map((s) => s.key));
    setBusy(true); setErr("");
    try {
      setLib(await saveAgencyStyle(k, from
        ? { name: `${from.name} (cópia)`.slice(0, 60), spec: from.spec, notes: `Duplicado de ${from.key} v${from.version}.`, source_url: from.source_url, transformation: from.transformation, platforms: from.platforms }
        : { name: `Estilo ${k}`, spec: EMPTY }, 0));
      setOpen(k);
    } catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Estilos de edição</h1>
          <p className="text-sm text-muted-foreground">A biblioteca da agência. Cada estilo tem versões e importa-se para os clientes que escolheres: o cliente fica com uma cópia fixa até carregares em &quot;Atualizar&quot;. A equipa dos clientes não vê esta página.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => void create()} disabled={busy || !lib}><PlusIcon /> Estilo novo</Button>
          <Button size="sm" variant="outline" onClick={() => void reload()}><RotateCwIcon /> Atualizar</Button>
        </div>
      </div>
      {err && <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">{err}<Button size="sm" variant="outline" onClick={() => void reload()}>Tentar de novo</Button></AlertDescription></Alert>}
      {!lib && !err && <Skeleton className="h-64 w-full" aria-busy="true" />}
      {lib && (
        <>
          {archived > 0 && (
            <label className="flex items-center gap-1.5 text-sm"><input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} />Mostrar arquivados ({archived})</label>
          )}
          {lib.styles.length === 0 ? (
            <p className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">Ainda não há estilos na biblioteca. Carrega em &quot;Estilo novo&quot;.</p>
          ) : (
            <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6" aria-label="Biblioteca de estilos">
              {visible.map((s) => (
                <li key={s.key}>
                  <button type="button" data-style={s.key} onClick={() => setOpen(s.key)}
                    className={cn("flex w-full flex-col gap-2 rounded-lg border p-2 text-left transition-colors hover:bg-muted/60", s.status === "arquivado" && "opacity-60")}>
                    <StylePreview spec={s.spec} />
                    <span className="truncate text-sm font-medium">{s.key} · {s.name}</span>
                    <span className="flex flex-wrap items-center gap-1">
                      <Badge variant={statusVariant(s.status)}>{STATUS_LABEL[s.status]}</Badge>
                      <span className="text-xs text-muted-foreground">v{s.version}</span>
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {s.imports.length ? `Em ${s.imports.length} cliente${s.imports.length === 1 ? "" : "s"}` : "Em nenhum cliente"}
                      {s.imports.some((i) => i.version < s.version) ? " · há clientes por atualizar" : ""}
                    </span>
                    {!isRenderable(s.key) && <span className="text-xs text-amber-500">Sem render ainda</span>}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      <Sheet open={!!current} onOpenChange={(o) => { if (!o) setOpen(null); }}>
        <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
          {current && lib && (
            <>
              <SheetHeader>
                <SheetTitle>{current.key} · {current.name}</SheetTitle>
                <SheetDescription>Gravar cria uma versão nova. Os clientes ficam na versão que importaram até carregares em &quot;Atualizar&quot;.</SheetDescription>
              </SheetHeader>
              <StyleSheet key={`${current.key}-${current.version}`} style={current} lib={lib} onSaved={setLib} onDuplicate={() => void create(current)} />
            </>
          )}
        </SheetContent>
      </Sheet>
    </div>
  );
}

function StyleSheet({ style, lib, onSaved, onDuplicate }: { style: AgencyStyle; lib: AgencyLibrary; onSaved: (l: AgencyLibrary) => void; onDuplicate: () => void }) {
  const [name, setName] = useState(style.name);
  const [notes, setNotes] = useState(style.notes ?? "");
  const [source, setSource] = useState(style.source_url ?? "");
  const [specText, setSpecText] = useState(JSON.stringify(style.spec, null, 2));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");
  const [renameFor, setRenameFor] = useState<{ ws: string; key: string } | null>(null);
  const parsed = useMemo((): { spec: StyleSpec | null; error: string } => {
    try { return { spec: JSON.parse(specText) as StyleSpec, error: "" }; } catch (e) { return { spec: null, error: `JSON inválido: ${(e as Error).message}` }; }
  }, [specText]);
  const problems = parsed.spec ? specProblems(parsed.spec, style.status === "ativo") : [parsed.error];
  const ro = style.status === "arquivado";

  const run = async (f: () => Promise<AgencyLibrary>, done: string) => {
    setBusy(true); setErr(""); setOk("");
    try { onSaved(await f()); setOk(done); return true; }
    catch (e) { setErr((e as Error).message); return false; }
    finally { setBusy(false); }
  };
  const doImport = async (ws: string, as?: string) => {
    setBusy(true); setErr(""); setOk("");
    try { onSaved(await importAgencyStyle(style.key, ws, as)); setOk("Importado. O cliente já o tem no catálogo e no editor."); setRenameFor(null); }
    catch (e) {
      const c = (e as { code?: string }).code;
      if (c === "PT409") setRenameFor({ ws, key: `${style.key}A` });
      setErr((e as Error).message);
    } finally { setBusy(false); }
  };
  const imported = new Map(style.imports.map((i) => [i.ws, i]));

  return (
    <div className="flex flex-col gap-4 px-4 pb-8 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={statusVariant(style.status)}>{STATUS_LABEL[style.status]}</Badge>
        <span className="text-muted-foreground">versão {style.version}{style.updated_label ? ` · ${style.updated_label}` : ""}</span>
      </div>
      <div className="grid gap-4 sm:grid-cols-[minmax(0,180px)_1fr]">
        <StylePreview spec={parsed.spec} boxes />
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1">Nome<Input value={name} maxLength={60} disabled={ro} onChange={(e) => setName(e.target.value)} /></label>
          <label className="flex flex-col gap-1">Vídeo de origem ou inspiração (link)
            <Input value={source} maxLength={500} disabled={ro} placeholder="https://www.instagram.com/reel/…" onChange={(e) => setSource(e.target.value)} /></label>
          <label className="flex flex-col gap-1">Notas<Textarea rows={3} maxLength={2000} value={notes} disabled={ro} onChange={(e) => setNotes(e.target.value)} /></label>
        </div>
      </div>
      <label className="flex flex-col gap-1">Layout (JSON: camadas com tipo e caixa [x, y, largura, altura] em 1080×1920)
        <Textarea rows={10} spellCheck={false} className="font-mono text-xs" value={specText} disabled={ro} aria-invalid={problems.length > 0} onChange={(e) => setSpecText(e.target.value)} />
      </label>
      {problems.length > 0 && <Alert variant="destructive"><AlertDescription><ul className="list-disc pl-4">{problems.map((p) => <li key={p}>{p}</li>)}</ul></AlertDescription></Alert>}
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      {ok && <p role="status" className="text-emerald-600">{ok}</p>}
      <div className="flex flex-wrap gap-2">
        {!ro && <Button disabled={busy || problems.length > 0}
          onClick={() => void run(() => saveAgencyStyle(style.key, { name, notes, source_url: source, spec: parsed.spec! }, style.version), "Gravado como versão nova.")}>Gravar versão nova</Button>}
        {style.status === "rascunho" && <Button variant="outline" disabled={busy} onClick={() => void run(() => setAgencyStyleStatus(style.key, "ativo"), "Estilo ativo: já se pode importar.")}>Ativar</Button>}
        {style.status === "ativo" && <Button variant="outline" disabled={busy} onClick={() => void run(() => setAgencyStyleStatus(style.key, "rascunho"), "Voltou a rascunho.")}>Passar a rascunho</Button>}
        <Button variant="outline" disabled={busy} onClick={onDuplicate}><CopyIcon /> Duplicar e ajustar</Button>
        {style.status !== "arquivado"
          ? <Button variant="ghost" disabled={busy} onClick={() => void run(() => setAgencyStyleStatus(style.key, "arquivado"), "Arquivado. Os clientes que o têm continuam com a sua cópia.")}>Arquivar</Button>
          : <Button variant="outline" disabled={busy} onClick={() => void run(() => setAgencyStyleStatus(style.key, "rascunho"), "Recuperado como rascunho.")}>Recuperar</Button>}
      </div>

      <section aria-label="Clientes" className="flex flex-col gap-2 border-t pt-3">
        <h3 className="font-medium">Clientes</h3>
        {!lib.can_import && <p className="text-muted-foreground">Não tens permissão para importar estilos para clientes.</p>}
        {style.status !== "ativo" && <p className="text-muted-foreground">Ativa o estilo para o poderes importar.</p>}
        {lib.clients.length === 0 && <p className="text-muted-foreground">Não há clientes onde possas gerir estilos.</p>}
        <ul className="flex flex-col gap-1.5">
          {lib.clients.map((c) => {
            const i = imported.get(c.ws);
            return (
              <li key={c.ws} className="flex flex-wrap items-center justify-between gap-2 rounded-md border px-3 py-2">
                <span>{c.name}{i ? <span className="text-muted-foreground"> · tem {i.key} v{i.version}{i.status !== "ativo" ? ` (${STATUS_LABEL[i.status].toLowerCase()})` : ""}</span> : null}</span>
                {lib.can_import && style.status === "ativo" && (
                  !i ? <Button size="sm" variant="outline" disabled={busy} onClick={() => void doImport(c.ws)}>Importar</Button>
                    : i.version < style.version || i.status !== "ativo"
                      ? <Button size="sm" variant="outline" disabled={busy} onClick={() => void doImport(c.ws, i.key)}>Atualizar para v{style.version}</Button>
                      : <span className="text-xs text-emerald-600">Em dia</span>
                )}
                {renameFor?.ws === c.ws && (
                  <form className="flex w-full flex-wrap items-center gap-2" onSubmit={(e) => { e.preventDefault(); void doImport(c.ws, renameFor.key.trim().toUpperCase()); }}>
                    <span className="text-xs text-muted-foreground">Importar com a chave</span>
                    <Input className="h-8 w-28" aria-label="Chave no cliente" maxLength={16} value={renameFor.key} onChange={(e) => setRenameFor({ ws: c.ws, key: e.target.value })} />
                    <Button size="sm" type="submit" disabled={busy}>Importar</Button>
                  </form>
                )}
              </li>
            );
          })}
        </ul>
        {!isRenderable(style.key) && <p className="text-xs text-amber-500">O motor ainda não desenha {style.key}: no cliente aparece no catálogo mas não no editor.</p>}
      </section>
    </div>
  );
}
