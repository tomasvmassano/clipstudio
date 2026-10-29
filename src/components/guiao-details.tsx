"use client";

import { useEffect, useState } from "react";
import { Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import type { ScriptActions } from "@/components/use-guioes";
import { KIND_LABEL, PLATFORMS, onProjectsChanged, parseTags, type Owner, type Project, type ProjectList } from "@/lib/projects";
import type { Guiao } from "@/lib/types";

/** Campanhas e pessoas do cliente, partilhadas por todos os cartões (um pedido por cliente). */
export function useMetaLists(actions: ScriptActions) {
  const [projects, setProjects] = useState<ProjectList | null>(null);
  const [owners, setOwners] = useState<Owner[] | null>(null);
  const [err, setErr] = useState("");
  useEffect(() => {
    let alive = true;
    Promise.all([actions.projects(), actions.owners()])
      .then(([p, o]) => { if (alive) { setProjects(p); setOwners(o); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    const off = onProjectsChanged(() => { actions.projects().then((p) => { if (alive) setProjects(p); }).catch(() => {}); });
    return () => { alive = false; off(); };
  }, [actions]);
  return { projects, owners, err, setProjects };
}

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm";

/** Campanha, responsável, plataformas e etiquetas de um guião (FR-02-03). Não mexe no texto nem na aprovação. */
export function DetailsSheet({ g, open, onOpenChange, actions, canEdit, canProjects }: {
  g: Guiao; open: boolean; onOpenChange: (o: boolean) => void; actions: ScriptActions; canEdit: boolean; canProjects: boolean;
}) {
  const { projects, owners, err: listErr, setProjects } = useMetaLists(actions);
  const [project, setProject] = useState(g.project_id ?? "");
  const [owner, setOwner] = useState(g.owner_id ?? "");
  const [platforms, setPlatforms] = useState<string[]>(g.platforms ?? []);
  const [tags, setTags] = useState((g.tags ?? []).join(", "));
  const [newName, setNewName] = useState("");
  const [newKind, setNewKind] = useState<Project["kind"]>("campanha");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");

  const choosable = (projects?.projects ?? []).filter((p) => p.status === "ativa" || p.id === g.project_id);
  const ro = !canEdit;

  const create = async () => {
    setBusy(true); setErr("");
    try {
      const r = await actions.saveProject(null, { name: newName.trim(), kind: newKind });
      setProjects(r);
      const made = r.projects.find((p) => p.name.trim().toLowerCase() === newName.trim().toLowerCase());
      if (made) setProject(made.id);
      setNewName("");
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const save = async () => {
    setBusy(true); setErr(""); setOk("");
    try {
      await actions.meta(g.id, { project_id: project || null, owner_id: owner || null, platforms, tags: parseTags(tags) });
      setOk("Guardado.");
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-md">
        <SheetHeader>
          <SheetTitle>Detalhes do guião {g.n}</SheetTitle>
          <SheetDescription>Campanha, responsável, plataformas e etiquetas. Mudar isto não cria versão nem tira a aprovação.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-8 text-sm">
          {listErr && <Alert variant="destructive"><AlertDescription>Não deu para ler as campanhas ou as pessoas: {listErr}</AlertDescription></Alert>}
          <label className="flex flex-col gap-1">Campanha ou série
            <select className={selectCls} value={project} disabled={ro || !projects} onChange={(e) => setProject(e.target.value)}>
              <option value="">Sem campanha</option>
              {choosable.map((p) => <option key={p.id} value={p.id}>{KIND_LABEL[p.kind]} · {p.name}{p.status === "arquivada" ? " (arquivada)" : ""}</option>)}
            </select>
          </label>
          {canProjects && !ro && (
            <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); if (newName.trim()) void create(); }}>
              <label className="flex min-w-[10rem] flex-1 flex-col gap-1">Nova
                <Input value={newName} maxLength={80} placeholder="Ex.: Black Friday" onChange={(e) => setNewName(e.target.value)} />
              </label>
              <select aria-label="Tipo" className="h-9 rounded-md border bg-background px-2" value={newKind} onChange={(e) => setNewKind(e.target.value as Project["kind"])}>
                <option value="campanha">Campanha</option>
                <option value="serie">Série</option>
              </select>
              <Button type="submit" size="sm" variant="outline" disabled={busy || !newName.trim()}>Criar</Button>
            </form>
          )}
          <label className="flex flex-col gap-1">Responsável
            <select className={selectCls} value={owner} disabled={ro || !owners} onChange={(e) => setOwner(e.target.value)}>
              <option value="">Ninguém</option>
              {(owners ?? []).map((o) => <option key={o.user_id} value={o.user_id}>{o.label}</option>)}
              {g.owner_id && owners && !owners.some((o) => o.user_id === g.owner_id) && <option value={g.owner_id}>Sem acesso atual</option>}
            </select>
          </label>
          <fieldset className="flex flex-col gap-1">
            <legend className="mb-1">Plataformas</legend>
            <div className="flex flex-wrap gap-3">
              {PLATFORMS.map((p) => (
                <label key={p.v} className="flex items-center gap-1.5">
                  <input type="checkbox" disabled={ro} checked={platforms.includes(p.v)}
                    onChange={(e) => setPlatforms((l) => (e.target.checked ? [...l, p.v] : l.filter((x) => x !== p.v)))} />
                  {p.l}
                </label>
              ))}
            </div>
          </fieldset>
          <label className="flex flex-col gap-1">Etiquetas (separadas por vírgula)
            <Input value={tags} disabled={ro} placeholder="relações, dinheiro" onChange={(e) => setTags(e.target.value)} />
          </label>
          {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
          {ok && <p role="status" className="text-emerald-600">{ok}</p>}
          {canEdit && (
            <div className="flex gap-2">
              <Button onClick={() => void save()} disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button>
              <Button variant="ghost" onClick={() => onOpenChange(false)}>Fechar</Button>
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

/** Nomes para mostrar no cartão. */
export function metaNames(g: Guiao, projects: ProjectList | null, owners: Owner[] | null) {
  return {
    project: g.project_id ? projects?.projects.find((p) => p.id === g.project_id) ?? null : null,
    owner: g.owner_id ? owners?.find((o) => o.user_id === g.owner_id)?.label ?? null : null,
  };
}
