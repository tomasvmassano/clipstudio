"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  createContent, duplicateContent, fetchGuioes, fetchHistory, restoreVersion, saveContent, setProduction, subscribeGuioes, transitionContent,
} from "@/lib/data";
import type { Access } from "@/lib/access";
import type { BriefFields, ContentContext, ContentHistory, ContentPatch, EditorialTarget, Guiao, Reference, Source } from "@/lib/types";
import { fetchContext, fetchSources, linkSource, saveBrief } from "@/lib/sources";
import { fetchReferences, linkReference } from "@/lib/references";
import { useSession } from "@/components/session-provider";
import { fetchOwners, fetchProjects, saveProject, setContentMeta, type MetaPatch, type Owner, type Project, type ProjectList } from "@/lib/projects";

/** O que o utilizador pode fazer aos guiões neste workspace (o servidor volta a verificar cada ação). */
export type ScriptCaps = {
  create: boolean; edit: boolean; submit: boolean; approve: boolean; reject: boolean; archive: boolean; record: boolean; export: boolean; refs: boolean;
  comment: boolean;
  /** gerir campanhas e séries */
  projects: boolean;
};

/** Ações sobre um guião; cada uma devolve a linha atualizada e já a põe na lista. */
export type ScriptActions = {
  save: (id: string, p: ContentPatch, lock?: number) => Promise<Guiao>;
  transition: (id: string, to: EditorialTarget, reason?: string, lock?: number) => Promise<Guiao>;
  record: (id: string, recorded: boolean) => Promise<Guiao>;
  duplicate: (id: string) => Promise<Guiao>;
  restore: (id: string, versionId: string, lock?: number) => Promise<Guiao>;
  history: (id: string) => Promise<ContentHistory>;
  context: (id: string) => Promise<ContentContext>;
  saveBrief: (id: string, f: BriefFields) => Promise<ContentContext>;
  link: (id: string, sourceId: number, link: boolean) => Promise<ContentContext>;
  sources: () => Promise<Source[]>;
  references: () => Promise<Reference[]>;
  linkRef: (id: string, refId: number, link: boolean) => Promise<ContentContext>;
  reload: () => Promise<void>;
  /** Campanha, responsável, plataformas e etiquetas (W2-07): não cria versão. */
  meta: (id: string, patch: MetaPatch) => Promise<Guiao>;
  projects: (fresh?: boolean) => Promise<ProjectList>;
  saveProject: (id: string | null, fields: Partial<Pick<Project, "name" | "kind" | "status" | "starts_on" | "ends_on">>) => Promise<ProjectList>;
  owners: () => Promise<Owner[]>;
};

/** Guiões de um dia (mais os de dias anteriores por gravar), ao vivo. */
export function useGuioes(access: Access, date: string) {
  const [all, setAll] = useState<Guiao[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const reload = useCallback(async () => {
    try {
      setAll(await fetchGuioes(access, date));
      setError("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [access, date]);

  useEffect(() => {
    let alive = true;
    fetchGuioes(access, date)
      .then((x) => { if (alive) { setAll(x); setError(""); } })
      .catch((e: Error) => { if (alive) setError(e.message); })
      .finally(() => { if (alive) setLoading(false); });
    const unsub = subscribeGuioes(access, reload);
    return () => { alive = false; unsub(); };
  }, [access, date, reload]);

  const put = useCallback((g: Guiao) => {
    setAll((prev) => (prev.some((x) => x.id === g.id) ? prev.map((x) => (x.id === g.id ? g : x)) : [...prev, g].sort((a, b) => a.date.localeCompare(b.date) || a.n - b.n)));
    return g;
  }, []);

  const actions = useScriptActions(access, put, reload);

  const create = useCallback(async (d: string) => put(await createContent(access, { date: d, corpo: "Escreve aqui o corpo do guião.", hooks: [{ text: "", mecanismo: "" }] })), [access, put]);

  const caps = useScriptCaps();
  const canWrite = caps.approve || caps.reject || caps.edit || caps.record;

  return { all, loading, error, reload, actions, create, caps, canWrite };
}

/** Capacidades sobre guiões no cliente aberto (a UI só esconde; o servidor decide). */
export function useScriptCaps(): ScriptCaps {
  const { can } = useSession();
  return {
    create: can("scripts.create"),
    edit: can("scripts.edit"),
    submit: can("scripts.submit"),
    approve: can("scripts.approve"),
    reject: can("scripts.reject"),
    archive: can("scripts.delete"),
    record: can("recording.confirm"),
    export: can("scripts.export"),
    refs: can("references.read"),
    comment: can("review.comment"),
    projects: can("projects.manage"),
  };
}

/** Ações sobre guiões; put recebe cada linha atualizada, reload recarrega a lista de quem as usa. */
export function useScriptActions(access: Access, put: (g: Guiao) => Guiao, reload: () => Promise<void>): ScriptActions {
  return useMemo<ScriptActions>(() => ({
    save: async (id, p, lock) => {
      try { return put(await saveContent(access, id, p, lock)); }
      catch (e) { if ((e as { code?: string }).code === "PT409") await reload(); throw e; }
    },
    transition: async (id, to, reason, lock) => {
      try { return put(await transitionContent(access, id, to, reason, lock)); }
      catch (e) { if ((e as { code?: string }).code === "PT409") await reload(); throw e; }
    },
    record: async (id, recorded) => put(await setProduction(access, id, recorded ? "recorded" : "not_started")),
    meta: async (id, patch) => put(await setContentMeta(access, id, patch)),
    projects: (fresh) => fetchProjects(access, fresh),
    saveProject: (id, fields) => saveProject(access, id, fields),
    owners: () => fetchOwners(access),
    duplicate: async (id) => put(await duplicateContent(access, id)),
    restore: async (id, versionId, lock) => put(await restoreVersion(access, id, versionId, lock)),
    history: (id: string) => fetchHistory(access, id),
    context: (id: string) => fetchContext(access, id),
    saveBrief: (id: string, f: BriefFields) => saveBrief(access, id, f),
    link: (id: string, sourceId: number, l: boolean) => linkSource(access, id, sourceId, l),
    sources: () => fetchSources(access, {}, 300),
    references: () => fetchReferences(access),
    linkRef: async (id: string, refId: number, l: boolean) => { await linkReference(access, refId, { content: id }, l); return fetchContext(access, id); },
    reload,
  }), [access, put, reload]);
}
