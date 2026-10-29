"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import {
  fetchCatalog, initCatalog, savePreset, saveStyle, setStyleStatus, specProblems, styleHistory,
  LAYER_LABEL, OUTPUT_LABEL, PLATFORM_LABEL, SAFE, STATUS_LABEL, TRANSFORMATION_LABEL,
  type EditCatalog, type EditStyle, type Platform, type PresetOutput, type StyleSpec, type StyleVersion, type Transformation,
} from "@/lib/edit-styles";
import { cn } from "@/lib/utils";

/*
 * Estilos de edição (VAR-02) e preset do cliente (EDL-01). O preset diz o que o pacote automático gera por guião;
 * cada estilo é um template versionado. Gravar cria sempre uma versão nova; o preset fixa a versão que usa.
 */

const LAYER_FILL: Record<string, string> = {
  video: "#3b82f6", image: "#8b5cf6", attention_video: "#14b8a6", title: "#facc15", captions: "#f97316", band: "#ef4444",
};
const when = (iso: string) => new Date(iso).toLocaleString("pt-PT", { timeZone: "Asia/Dubai", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/** Pré-visualização do layout em 1080×1920 com o retângulo seguro a tracejado. */
function Preview({ spec, className }: { spec: StyleSpec | null; className?: string }) {
  const layers = Array.isArray(spec?.layers) ? spec!.layers : [];
  return (
    <svg viewBox="0 0 1080 1920" role="img" aria-label={layers.length ? `Layout com ${layers.length} camadas` : "Layout ainda por desenhar"}
      className={cn("h-auto w-full rounded-md border bg-neutral-950", className)}>
      {layers.map((l, i) => Array.isArray(l?.box) && l.box.length === 4 ? (
        <g key={i}>
          <rect x={l.box[0]} y={l.box[1]} width={Math.max(0, l.box[2])} height={Math.max(0, l.box[3])}
            fill={l.color ?? LAYER_FILL[l.kind] ?? "#64748b"} fillOpacity={l.kind === "title" || l.kind === "captions" ? 0.85 : 0.45}
            stroke={l.stroke ?? "none"} strokeWidth={l.stroke ? 8 : 0} />
          <text x={l.box[0] + 24} y={l.box[1] + 70} fontSize={56} fill={l.kind === "title" ? "#000" : "#fff"} fontWeight={700}>
            {LAYER_LABEL[l.kind] ?? l.kind}{l.role ? ` · ${l.role}` : ""}
          </text>
        </g>
      ) : null)}
      <rect x={SAFE.x0} y={SAFE.y0} width={SAFE.x1 - SAFE.x0} height={SAFE.y1 - SAFE.y0} fill="none" stroke="#e5e7eb" strokeWidth={6} strokeDasharray="30 20" />
      {!layers.length && <text x={540} y={980} textAnchor="middle" fontSize={64} fill="#9ca3af">Layout por desenhar</text>}
    </svg>
  );
}

function statusVariant(s: EditStyle["status"]) {
  return s === "ativo" ? "default" : s === "arquivado" ? "outline" : "secondary";
}

function StyleEditor({ access, style, canManage, onSaved, onClose }: {
  access: Access; style: EditStyle; canManage: boolean; onSaved: (c: EditCatalog) => void; onClose: () => void;
}) {
  const [name, setName] = useState(style.name);
  const [transformation, setTransformation] = useState<Transformation | "">(style.transformation ?? "");
  const [platforms, setPlatforms] = useState<Platform[]>(style.platforms);
  const [notes, setNotes] = useState(style.notes ?? "");
  const [specText, setSpecText] = useState(() => JSON.stringify(style.spec, null, 2));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");
  const [history, setHistory] = useState<StyleVersion[] | null>(null);
  const [histErr, setHistErr] = useState("");

  const parsed = useMemo((): { spec: StyleSpec | null; error: string } => {
    try { return { spec: JSON.parse(specText) as StyleSpec, error: "" }; } catch (e) { return { spec: null, error: `JSON inválido: ${(e as Error).message}` }; }
  }, [specText]);
  const problems = parsed.spec ? specProblems(parsed.spec, style.status === "ativo") : [parsed.error];
  const ro = !canManage || style.status === "arquivado";

  const loadHistory = useCallback(() => {
    styleHistory(access, style.key).then((h) => { setHistory(h); setHistErr(""); }).catch((e: Error) => setHistErr(e.message));
  }, [access, style.key]);
  useEffect(() => { loadHistory(); }, [loadHistory, style.version]);

  const run = async (f: () => Promise<EditCatalog>, done: string) => {
    setBusy(true); setErr(""); setOk("");
    try { onSaved(await f()); setOk(done); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  const save = () => {
    if (!parsed.spec || problems.length) return;
    void run(() => saveStyle(access, style.key, { name, transformation: transformation || null, platforms, notes, spec: parsed.spec! }, style.version), "Gravado como versão nova.");
  };

  return (
    <div className="flex flex-col gap-4 px-4 pb-8">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <Badge variant={statusVariant(style.status)}>{STATUS_LABEL[style.status]}</Badge>
        <span className="text-muted-foreground">versão {style.version} · {when(style.updated_at)}{style.updated_label ? ` · ${style.updated_label}` : ""}</span>
      </div>
      <div className="grid gap-4 sm:grid-cols-[minmax(0,180px)_1fr]">
        <Preview spec={parsed.spec} />
        <div className="flex flex-col gap-3 text-sm">
          <label className="flex flex-col gap-1">Nome
            <Input value={name} maxLength={60} disabled={ro} onChange={(e) => setName(e.target.value)} />
          </label>
          <label className="flex flex-col gap-1">Nível de transformação
            <select className="h-8 rounded-md border bg-background px-2" value={transformation} disabled={ro}
              onChange={(e) => setTransformation(e.target.value as Transformation | "")}>
              <option value="">Por definir</option>
              {(Object.keys(TRANSFORMATION_LABEL) as Transformation[]).map((t) => <option key={t} value={t}>{TRANSFORMATION_LABEL[t]}</option>)}
            </select>
          </label>
          <fieldset className="flex flex-col gap-1">
            <legend className="mb-1">Plataforma preferida</legend>
            <div className="flex flex-wrap gap-2">
              {(Object.keys(PLATFORM_LABEL) as Platform[]).map((p) => (
                <label key={p} className="flex items-center gap-1.5">
                  <input type="checkbox" disabled={ro} checked={platforms.includes(p)}
                    onChange={(e) => setPlatforms((l) => (e.target.checked ? [...l, p] : l.filter((x) => x !== p)))} />
                  {PLATFORM_LABEL[p]}
                </label>
              ))}
            </div>
          </fieldset>
        </div>
      </div>
      <label className="flex flex-col gap-1 text-sm">Notas
        <Textarea rows={3} maxLength={2000} value={notes} disabled={ro} onChange={(e) => setNotes(e.target.value)} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Layout (JSON: camadas com tipo e caixa [x, y, largura, altura] em 1080×1920)
        <Textarea rows={12} spellCheck={false} className="font-mono text-xs" value={specText} disabled={ro}
          aria-invalid={problems.length > 0} onChange={(e) => setSpecText(e.target.value)} />
      </label>
      <p className="text-xs text-muted-foreground">
        Tipos: {Object.entries(LAYER_LABEL).map(([k, v]) => `${k} (${v})`).join(", ")}. Texto (título, legendas) fica dentro do tracejado: x 60-960, y 210-1600.
      </p>
      {problems.length > 0 && (
        <Alert variant="destructive"><AlertDescription><ul className="list-disc pl-4">{problems.map((p) => <li key={p}>{p}</li>)}</ul></AlertDescription></Alert>
      )}
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      {ok && <p role="status" className="text-sm text-emerald-600">{ok}</p>}
      {canManage && (
        <div className="flex flex-wrap gap-2">
          {style.status !== "arquivado" && <Button onClick={save} disabled={busy || problems.length > 0}>Gravar versão nova</Button>}
          {style.status === "rascunho" && <Button variant="outline" disabled={busy} onClick={() => void run(() => setStyleStatus(access, style.key, "ativo"), "Estilo ativo.")}>Ativar</Button>}
          {style.status === "ativo" && <Button variant="outline" disabled={busy} onClick={() => void run(() => setStyleStatus(access, style.key, "rascunho"), "Voltou a rascunho.")}>Passar a rascunho</Button>}
          {style.status !== "arquivado"
            ? <Button variant="ghost" disabled={busy} onClick={() => void run(() => setStyleStatus(access, style.key, "arquivado"), "Arquivado.")}>Arquivar</Button>
            : <Button variant="outline" disabled={busy} onClick={() => void run(() => setStyleStatus(access, style.key, "rascunho"), "Recuperado como rascunho.")}>Recuperar</Button>}
          <Button variant="ghost" onClick={onClose}>Fechar</Button>
        </div>
      )}
      <section aria-label="Versões" className="flex flex-col gap-1 border-t pt-3 text-sm">
        <h3 className="font-medium">Versões</h3>
        {histErr && <p role="alert" className="text-destructive">Não deu para ler as versões: {histErr} <button type="button" className="underline" onClick={loadHistory}>Tentar de novo</button></p>}
        {!history && !histErr && <Skeleton className="h-10 w-full" />}
        {history?.map((v) => (
          <div key={v.version} className="flex flex-wrap justify-between gap-2 text-muted-foreground">
            <span>v{v.version} · {v.name}</span>
            <span>{when(v.created_at)}{v.created_label ? ` · ${v.created_label}` : ""}</span>
          </div>
        ))}
      </section>
    </div>
  );
}

function PresetEditor({ access, cat, onSaved }: { access: Access; cat: EditCatalog; onSaved: (c: EditCatalog) => void }) {
  const preset = cat.preset;
  const active = cat.styles.filter((s) => s.status === "ativo");
  const initial = useMemo(() => preset?.outputs ?? [], [preset]);
  const [outs, setOuts] = useState<PresetOutput[]>(initial);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const has = (k: PresetOutput["kind"], style?: string) => outs.some((o) => o.kind === k && (k !== "style" || o.style === style));
  const toggle = (o: PresetOutput, on: boolean) =>
    setOuts((l) => (on ? [...l, o] : l.filter((x) => !(x.kind === o.kind && (o.kind !== "style" || x.style === o.style)))));
  const captions = (o: PresetOutput) => outs.find((x) => x.kind === o.kind && (o.kind !== "style" || x.style === o.style))?.captions ?? "burned";
  const setCaptions = (o: PresetOutput, c: "burned" | "none") =>
    setOuts((l) => l.map((x) => (x.kind === o.kind && (o.kind !== "style" || x.style === o.style) ? { ...x, captions: c } : x)));
  const styleName = (k?: string) => cat.styles.find((s) => s.key === k)?.name ?? k;
  const label = (o: PresetOutput) => (o.kind === "style" ? `Estilo ${o.style} · ${styleName(o.style)}${o.style_version ? ` (v${o.style_version})` : ""}` : OUTPUT_LABEL[o.kind]);

  const save = async () => {
    setBusy(true); setErr("");
    try { const c = await savePreset(access, outs, preset?.version ?? 0); onSaved(c); setOuts(c.preset?.outputs ?? []); setEditing(false); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  const options: PresetOutput[] = [
    { kind: "master", per_hook: true, captions: "burned" }, { kind: "split_image_persona", captions: "burned" }, { kind: "split_attention", captions: "burned" },
    ...active.map((s) => ({ kind: "style" as const, style: s.key, captions: "burned" as const })),
  ];

  return (
    <section aria-label="Preset de edição" className="flex flex-col gap-3 rounded-lg border p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-lg font-semibold">Preset de edição</h2>
          <p className="text-sm text-muted-foreground">O que o pacote automático gera por cada guião gravado.
            {preset ? ` Versão ${preset.version} · ${when(preset.created_at)}${preset.created_label ? ` · ${preset.created_label}` : ""}.` : ""}</p>
        </div>
        {cat.can_manage && !editing && <Button variant="outline" onClick={() => { setOuts(initial); setEditing(true); }}>{preset ? "Mudar o preset" : "Criar o preset"}</Button>}
      </div>
      {preset?.stale && !editing && (
        <Alert><AlertDescription>Há estilos com versão nova ou que deixaram de estar ativos. O pacote continua a usar a versão fixada até gravares o preset de novo.</AlertDescription></Alert>
      )}
      {!editing ? (
        preset ? (
          <ol className="flex flex-col gap-1 text-sm" aria-label="Saídas do preset">
            {preset.outputs.map((o, i) => (
              <li key={i} className="flex flex-wrap justify-between gap-2 rounded-md bg-muted/50 px-3 py-2">
                <span>{label(o)}</span>
                <span className="text-muted-foreground">{o.captions === "burned" ? "legendas queimadas" : "sem legendas"}</span>
              </li>
            ))}
          </ol>
        ) : <p className="text-sm text-muted-foreground">Ainda sem preset. Sem ele o pacote automático não gera nada para este cliente.</p>
      ) : (
        <div className="flex flex-col gap-2 text-sm">
          {options.map((o) => {
            const on = has(o.kind, o.style);
            const id = `out-${o.kind}-${o.style ?? ""}`;
            return (
              <div key={id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border px-3 py-2">
                <label htmlFor={id} className="flex items-center gap-2">
                  <input id={id} type="checkbox" checked={on} onChange={(e) => toggle(o, e.target.checked)} />
                  {o.kind === "style" ? `Estilo ${o.style} · ${styleName(o.style)}` : OUTPUT_LABEL[o.kind]}
                </label>
                {on && (
                  <select aria-label={`Legendas: ${o.kind === "style" ? o.style : OUTPUT_LABEL[o.kind]}`} className="h-8 rounded-md border bg-background px-2"
                    value={captions(o)} onChange={(e) => setCaptions(o, e.target.value as "burned" | "none")}>
                    <option value="burned">Legendas queimadas</option>
                    <option value="none">Sem legendas</option>
                  </select>
                )}
              </div>
            );
          })}
          {active.length === 0 && <p className="text-muted-foreground">Ativa um estilo no catálogo para o poderes pôr no preset.</p>}
          {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
          <div className="flex gap-2">
            <Button onClick={() => void save()} disabled={busy || outs.length === 0}>Gravar preset</Button>
            <Button variant="ghost" onClick={() => { setEditing(false); setErr(""); }}>Cancelar</Button>
          </div>
        </div>
      )}
    </section>
  );
}

function EdicaoInner({ access }: { access: Access }) {
  const [cat, setCat] = useState<EditCatalog | null>(null);
  const [err, setErr] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const [newKey, setNewKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [showArchived, setShowArchived] = useState(false);

  const reload = useCallback(async () => {
    try { setCat(await fetchCatalog(access)); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => {
    let alive = true;
    fetchCatalog(access).then((c) => { if (alive) { setCat(c); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access]);

  const current = cat?.styles.find((s) => s.key === open) ?? null;
  const visible = (cat?.styles ?? []).filter((s) => showArchived || s.status !== "arquivado");
  const archived = (cat?.styles ?? []).filter((s) => s.status === "arquivado").length;

  const create = async () => {
    const k = newKey.trim().toUpperCase();
    setBusy(true); setErr("");
    try { setCat(await saveStyle(access, k, { name: k, spec: { canvas: { w: 1080, h: 1920 }, layers: [] } }, 0)); setNewKey(""); setOpen(k); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  const start = async () => {
    setBusy(true); setErr("");
    try { setCat(await initCatalog(access)); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Estilos de edição</h1>
          <p className="text-sm text-muted-foreground">O catálogo de estilos deste cliente e o que a edição automática gera por guião. A edição corre quando houver gravações ligadas ao motor.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => void reload()}><RotateCwIcon />Atualizar</Button>
      </div>
      {err && (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => void reload()}>Tentar de novo</Button></AlertDescription></Alert>
      )}
      {!cat && !err && <div className="flex flex-col gap-3" aria-busy="true"><Skeleton className="h-28 w-full" /><Skeleton className="h-64 w-full" /></div>}
      {cat && (
        <>
          <PresetEditor key={cat.preset?.version ?? 0} access={access} cat={cat} onSaved={setCat} />
          <section aria-label="Catálogo de estilos" className="flex flex-col gap-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-lg font-semibold">Catálogo</h2>
              <div className="flex flex-wrap items-center gap-2 text-sm">
                {archived > 0 && (
                  <label className="flex items-center gap-1.5"><input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} />Mostrar arquivados ({archived})</label>
                )}
                {cat.can_manage && cat.styles.length > 0 && (
                  <form className="flex items-center gap-2" onSubmit={(e) => { e.preventDefault(); void create(); }}>
                    <Input aria-label="Chave do estilo novo" placeholder="S14" className="h-8 w-24" value={newKey} maxLength={16} onChange={(e) => setNewKey(e.target.value)} />
                    <Button size="sm" type="submit" disabled={busy || !newKey.trim()}>Estilo novo</Button>
                  </form>
                )}
              </div>
            </div>
            {cat.styles.length === 0 ? (
              <div className="flex flex-col items-start gap-2 rounded-lg border border-dashed p-6 text-sm">
                <p>Este cliente ainda não tem estilos.</p>
                {cat.can_manage
                  ? <Button disabled={busy} onClick={() => void start()}>Começar pelo ponto de partida (S01 a S13 e preset por defeito)</Button>
                  : <p className="text-muted-foreground">Quem gere a edição deste cliente pode criá-los.</p>}
              </div>
            ) : (
              <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6 xl:grid-cols-7">
                {visible.map((s) => (
                  <li key={s.key}>
                    <button type="button" data-style={s.key} onClick={() => setOpen(s.key)}
                      className={cn("flex w-full flex-col gap-2 rounded-lg border p-2 text-left transition-colors hover:bg-muted/60", s.status === "arquivado" && "opacity-60")}>
                      <Preview spec={s.spec} />
                      <span className="flex items-center justify-between gap-1">
                        <span className="truncate text-sm font-medium">{s.key} · {s.name}</span>
                      </span>
                      <span className="flex flex-wrap items-center gap-1">
                        <Badge variant={statusVariant(s.status)}>{STATUS_LABEL[s.status]}</Badge>
                        <span className="text-xs text-muted-foreground">v{s.version}{s.transformation ? ` · transf. ${TRANSFORMATION_LABEL[s.transformation].toLowerCase()}` : ""}</span>
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
      <Sheet open={!!current} onOpenChange={(o) => { if (!o) setOpen(null); }}>
        <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
          {current && (
            <>
              <SheetHeader>
                <SheetTitle>{current.key} · {current.name}</SheetTitle>
                <SheetDescription>Gravar cria uma versão nova. O preset continua com a versão que fixou até ser gravado de novo.</SheetDescription>
              </SheetHeader>
              <StyleEditor key={current.key} access={access} style={current} canManage={!!cat?.can_manage}
                onSaved={setCat} onClose={() => setOpen(null)} />
            </>
          )}
        </SheetContent>
      </Sheet>
    </div>
  );
}

export default function EdicaoPage() {
  return (
    <Suspense fallback={null}>
      <WorkspaceGate need="scripts.read">{(access) => <EdicaoInner access={access} />}</WorkspaceGate>
    </Suspense>
  );
}
