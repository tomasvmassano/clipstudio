"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, RotateCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { DEFAULT_LOOK } from "@/components/edit/editor-stage";
import type { Access } from "@/lib/access";
import { applyStyle, fetchSavedStyles, saveStyleFromDoc, type EditState, type SavedStyles } from "@/lib/edit";
import { LOOK_LIMITS, setLook, type EditDoc, type TextLook } from "@/lib/edit-doc";
import { capStyleOf } from "@/lib/caption-plan";
import { optionText, type StyleOption } from "@/lib/style-options";

/* Aspeto e estilos guardados no editor (EDL-13, ADR-0050). O servidor lê a versão gravada e valida tudo. */

/** Aspeto das legendas e do hook (modo completo). Cada mudança entra no histórico do editor. */
export function LookPanel({ doc, disabled, onChange, styles, stylesError }: {
  doc: EditDoc; disabled: boolean; onChange: (d: EditDoc) => void;
  /** Estilos ativos do catálogo do cliente que o motor desenha (W10-41). */
  styles: StyleOption[]; stylesError?: string;
}) {
  const part = (key: "captions" | "hook", label: string) => {
    const l: TextLook = { ...DEFAULT_LOOK[key], ...(doc.look?.[key] ?? {}) };
    const set = (p: Partial<TextLook>) => onChange(setLook(doc, key, p));
    const extra = key === "captions" ? "highlight" : "background";
    return (
      <fieldset className="flex flex-col gap-1" disabled={disabled}>
        <legend className="font-medium">{label}</legend>
        <div className="flex flex-wrap items-center gap-3 text-xs">
          <label className="flex items-center gap-1">Cor <input type="color" value={l.color} onChange={(e) => set({ color: e.target.value.toUpperCase() })} aria-label={`Cor ${label}`} /></label>
          <label className="flex items-center gap-1">{key === "captions" ? "Palavra dita" : "Fundo"}
            <input type="checkbox" checked={!!l[extra]} onChange={(e) => set({ [extra]: e.target.checked ? (key === "captions" ? "#FFD400" : "#C8102E") : null })} aria-label={`${key === "captions" ? "Destacar a palavra dita" : "Fundo do hook"}`} />
            {l[extra] && <input type="color" value={l[extra] ?? "#000000"} onChange={(e) => set({ [extra]: e.target.value.toUpperCase() })} aria-label={`Cor ${key === "captions" ? "da palavra dita" : "do fundo"}`} />}
          </label>
          <label className="flex items-center gap-1"><input type="checkbox" checked={!!l.upper} onChange={(e) => set({ upper: e.target.checked })} /> Maiúsculas</label>
        </div>
        <label className="flex items-center gap-2 text-xs text-muted-foreground">Tamanho {l.size}
          <input type="range" min={LOOK_LIMITS.size[0]} max={LOOK_LIMITS.size[1]} value={l.size} onChange={(e) => set({ size: Number(e.target.value) })} aria-label={`Tamanho ${label}`} />
        </label>
        <label className="flex items-center gap-2 text-xs text-muted-foreground">Altura {l.y}
          <input type="range" min={LOOK_LIMITS.y[0]} max={LOOK_LIMITS.y[1]} step={10} value={l.y} onChange={(e) => set({ y: Number(e.target.value) })} aria-label={`Altura ${label}`} />
        </label>
      </fieldset>
    );
  };
  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1">
        <span className="font-medium">Estilo das legendas</span>
        <select aria-label="Estilo das legendas" className="h-9 max-w-64 rounded-md border bg-background px-2" disabled={disabled}
          value={doc.style || capStyleOf(doc)} onChange={(e) => onChange({ ...doc, style: e.target.value })}>
          {styles.map((o) => <option key={o.id} value={o.id}>{optionText(o)}</option>)}
        </select>
        <span className="text-xs text-muted-foreground">Os estilos ativos de &quot;Estilos de edição&quot; que o motor já desenha.{stylesError ? ` Não deu para ler o catálogo (${stylesError}).` : ""}</span>
      </label>
      {part("captions", "Legendas")}{part("hook", "Hook")}
    </div>
  );
}

/**
 * Estilos guardados do cliente: aplicar a este vídeo (versão nova) e, para quem gere estilos, guardar o aspeto da versão
 * gravada como estilo novo ou como versão nova de um estilo. Precisa da versão atual sem alterações por gravar.
 */
export function SavedStylesPanel({ access, st, dirty, canSave, onApplied }: {
  access: Access; st: EditState; dirty: boolean; canSave: boolean; onApplied: () => Promise<void>;
}) {
  const [data, setData] = useState<SavedStyles | null>(null);
  const [err, setErr] = useState("");
  const [pick, setPick] = useState("");
  const [target, setTarget] = useState("");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const cur = st.document?.current_version_id ?? null;
  const isCurrent = st.version?.id === cur;
  const load = useCallback(async () => {
    try { setData(await fetchSavedStyles(access)); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => { const id = setTimeout(() => void load(), 0); return () => clearTimeout(id); }, [load]);

  if (err) return (
    <div className="flex items-center gap-2 text-xs text-destructive">{err}
      <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Tentar de novo</Button></div>
  );
  if (!data) return <span className="text-xs text-muted-foreground" aria-busy="true">A carregar os estilos guardados…</span>;
  const styles = data.styles.filter((s) => s.status !== "arquivado");
  const blocked = dirty ? "Grava ou descarta as alterações primeiro." : !isCurrent ? "Abre a versão atual." : null;

  const apply = async () => {
    if (!cur || !pick) return;
    setBusy(true); setMsg(null);
    try { await applyStyle(access, st.asset.id, cur, pick); await onApplied(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); setBusy(false); }
  };
  const save = async () => {
    if (!cur) return;
    const ex = styles.find((s) => s.key === target);
    setBusy(true); setMsg(null);
    try {
      const r = await saveStyleFromDoc(access, st.asset.id, cur, ex ? ex.key : null, ex ? null : name.trim(), ex ? ex.version : null);
      setData(r); setName("");
      setMsg({ kind: "ok", text: ex ? `Estilo ${ex.name} atualizado (versão ${ex.version + 1}).` : "Estilo guardado. Já o podes aplicar a outros vídeos deste cliente." });
    } catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setBusy(false); }
  };

  return (
    <div className="flex flex-col gap-2">
      {styles.length === 0 ? <span className="text-muted-foreground">Ainda não há estilos guardados neste cliente.</span> : (
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Estilo guardado" className="h-9 max-w-64 rounded-md border bg-background px-2" value={pick} onChange={(e) => setPick(e.target.value)}>
            <option value="">Escolhe um estilo…</option>
            {styles.map((s) => <option key={s.key} value={s.key}>{s.name} ({s.key} v{s.version}){s.look.music ? ` · ${s.look.music.label}` : ""}</option>)}
          </select>
          <Button size="sm" variant="outline" disabled={!pick || busy || !!blocked} onClick={() => void apply()}>
            {busy ? <Loader2Icon className="animate-spin" /> : null} Aplicar a este vídeo
          </Button>
        </div>
      )}
      {canSave && data.can_manage && (
        <div className="flex flex-wrap items-center gap-2 border-t pt-2">
          <select aria-label="Guardar em" className="h-9 max-w-48 rounded-md border bg-background px-2" value={target} onChange={(e) => setTarget(e.target.value)}>
            <option value="">Estilo novo</option>
            {styles.map((s) => <option key={s.key} value={s.key}>Atualizar {s.name} ({s.key})</option>)}
          </select>
          {!target && <Input className="h-9 max-w-48" placeholder="Nome do estilo" value={name} maxLength={60} onChange={(e) => setName(e.target.value)} aria-label="Nome do estilo" />}
          <Button size="sm" variant="outline" disabled={busy || !!blocked || (!target && !name.trim())} onClick={() => void save()}>Guardar como estilo</Button>
        </div>
      )}
      {blocked && <span className="text-xs text-muted-foreground">{blocked}</span>}
      {msg && <span className={msg.kind === "err" ? "text-xs text-destructive" : "text-xs text-muted-foreground"} role="status">{msg.text}</span>}
    </div>
  );
}
