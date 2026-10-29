"use client";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowLeftIcon, BookmarkIcon, CalendarRangeIcon, CheckSquareIcon, FileTextIcon, HashIcon, Loader2Icon, NewspaperIcon, PaletteIcon, PlusIcon,
  SearchIcon, UserIcon,
} from "lucide-react";
import { useSession } from "@/components/session-provider";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Kbd } from "@/components/ui/kbd";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { ROLE_LABEL, type Access } from "@/lib/access";
import { createContent, todayDubai } from "@/lib/data";
import { saveProject } from "@/lib/projects";
import { createSource, duplicateOf } from "@/lib/sources";
import { createTask, STATUS_LABEL as TASK_STATUS } from "@/lib/tasks";
import { EDITORIAL_LABEL, SOURCE_STATUS_LABEL, type EditorialStatus, type SourceStatus } from "@/lib/types";
import { fetchSearchScope, searchGlobal, searchHref, type QuickActions, type SearchItem, type SearchResult, type SearchScope } from "@/lib/search";
import { clientPath } from "@/lib/ws-path";

/*
 * Paleta de comandos (FR-16-02) com pesquisa global (FR-16-01) e ações rápidas (FR-01-05). Ctrl/Cmd+K abre.
 * Só aparece quando a flag busca.global está ligada em pelo menos um cliente da pessoa (ADR-0035). O servidor filtra cada
 * resultado por cliente e por capacidade; as ações rápidas só aparecem se o servidor disser que a pessoa pode, e cada RPC
 * de criação volta a verificar.
 */

type Create = "source" | "script" | "project" | "task";
const CREATE_LABEL: Record<Create, string> = { source: "Nova fonte", script: "Novo guião", project: "Nova campanha", task: "Nova tarefa" };
const CREATE_FIELD: Record<Create, string> = { source: "Título da fonte", script: "Tema do guião", project: "Nome da campanha", task: "Título da tarefa" };
const CREATE_ICON: Record<Create, typeof PlusIcon> = { source: NewspaperIcon, script: FileTextIcon, project: CalendarRangeIcon, task: CheckSquareIcon };
const KIND_ICON: Record<string, typeof PlusIcon> = {
  script: FileTextIcon, source: NewspaperIcon, reference: BookmarkIcon, task: CheckSquareIcon, project: CalendarRangeIcon, person: UserIcon, style: PaletteIcon, tag: HashIcon,
};

type Option =
  | { type: "item"; key: string; item: SearchItem; group: string }
  | { type: "create"; key: string; create: Create; group: string };

function subtitle(it: SearchItem): string {
  switch (it.kind) {
    case "script": return [it.date, it.n != null ? `Guião ${it.n}` : null, it.status ? EDITORIAL_LABEL[it.status as EditorialStatus] ?? it.status : null].filter(Boolean).join(" · ");
    case "source": return [it.source_kind === "talent_request" ? "Pedido do talento" : "Fonte", it.status ? SOURCE_STATUS_LABEL[it.status as SourceStatus] ?? it.status : null].filter(Boolean).join(" · ");
    case "reference": return [it.creator ? `@${it.creator}` : null, it.tags?.length ? it.tags.map((t) => `#${t}`).join(" ") : null].filter(Boolean).join(" · ");
    case "task": return [it.status ? TASK_STATUS[it.status as keyof typeof TASK_STATUS] ?? it.status : null,
      it.due_at ? `prazo ${new Date(it.due_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}` : null].filter(Boolean).join(" · ");
    case "project": return [it.project_kind === "serie" ? "Série" : "Campanha", it.status === "arquivada" ? "arquivada" : null].filter(Boolean).join(" · ");
    case "person": return [it.email !== it.title ? it.email : null, it.job_title, it.role ? ROLE_LABEL[it.role] ?? it.role : null].filter(Boolean).join(" · ");
    case "style": return [it.status, it.version ? `versão ${it.version}` : null].filter(Boolean).join(" · ");
    case "tag": return `${it.count ?? 0} com esta etiqueta`;
  }
}

export function CommandPalette() {
  const { mode, ws, access } = useSession();
  const router = useRouter();
  const token = access?.token ?? null;
  const wsId = ws?.id ?? null;
  const [scope, setScope] = useState<SearchScope | null>(null);
  const [open, setOpen] = useState(false);

  const live = mode === "user" || mode === "code";
  const loadScope = useCallback(() => {
    if (!live) return Promise.resolve();
    return fetchSearchScope(wsId, token).then(setScope).catch(() => setScope(null));   // sem resposta: a paleta fica escondida
  }, [live, wsId, token]);
  useEffect(() => { void loadScope(); }, [loadScope]);

  const available = live && !!scope && scope.enabled.length > 0;
  useEffect(() => {
    if (!available) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [available]);
  // ao abrir, as ações rápidas voltam a vir do servidor (permissões podem ter mudado)
  useEffect(() => { if (open) void loadScope(); }, [open, loadScope]);

  if (!available) return null;
  // só corre no browser (a paleta não aparece antes de o servidor responder), por isso não há diferença de hidratação
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform);
  const wsEnabled = !!wsId && scope.enabled.some((w) => w.id === wsId);
  return (
    <>
      <Button variant="outline" size="sm" onClick={() => setOpen(true)} aria-label={isMac ? "Pesquisar (Cmd+K)" : "Pesquisar (Ctrl+K)"} className="gap-2 text-muted-foreground">
        <SearchIcon />
        <span className="hidden sm:inline">Pesquisar</span>
        <Kbd className="hidden md:inline-flex">{isMac ? "⌘K" : "Ctrl K"}</Kbd>
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="gap-0 p-0 sm:max-w-xl" showCloseButton={false}>
          {open && (
            <Palette
              key={wsId ?? "agencia"}
              wsId={wsEnabled ? wsId : null}
              wsName={ws?.name ?? null}
              multi={scope.enabled.length > 1}
              token={token}
              actions={wsEnabled && access ? scope.actions : null}
              access={wsEnabled ? access : null}
              onGo={(href) => { setOpen(false); router.push(href); }}
            />
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

function Palette({ wsId, wsName, multi, token, actions, access, onGo }: {
  wsId: string | null; wsName: string | null; multi: boolean; token: string | null; actions: QuickActions | null; access: Access | null;
  onGo: (href: string) => void;
}) {
  const [q, setQ] = useState("");
  const [onlyHere, setOnlyHere] = useState(!!wsId);
  const [res, setRes] = useState<SearchResult | null>(null);
  const [doneKey, setDoneKey] = useState("");
  const [err, setErr] = useState("");
  const [attempt, setAttempt] = useState(0);
  const [active, setActive] = useState(0);
  const [creating, setCreating] = useState<Create | null>(null);
  const reqId = useRef(0);
  const listId = useId();
  const inputRef = useRef<HTMLInputElement>(null);

  const reqKey = `${attempt}:${onlyHere ? 1 : 0}:${q}`;
  const loading = doneKey !== reqKey;
  useEffect(() => {
    const my = ++reqId.current;
    const t = setTimeout(() => {
      searchGlobal(q, onlyHere ? wsId : null, token)
        .then((r) => { if (reqId.current === my) { setRes(r); setErr(""); setActive(0); } })
        .catch((e: Error) => { if (reqId.current === my) setErr(e.message); })
        .finally(() => { if (reqId.current === my) setDoneKey(reqKey); });
    }, q ? 200 : 0);
    return () => clearTimeout(t);
  }, [q, onlyHere, wsId, token, reqKey]);

  const creates = useMemo<Create[]>(() => (actions ? (["script", "source", "project", "task"] as Create[]).filter((k) => actions[k]) : []), [actions]);
  const options = useMemo<Option[]>(() => {
    const o: Option[] = [];
    for (const g of res?.groups ?? []) for (const it of g.items) o.push({ type: "item", key: `${it.kind}:${it.ws ?? ""}:${it.id}`, item: it, group: g.label });
    for (const c of creates) o.push({ type: "create", key: `create:${c}`, create: c, group: "Criar neste cliente" });
    return o;
  }, [res, creates]);

  const choose = (o: Option | undefined) => {
    if (!o) return;
    if (o.type === "create") { setCreating(o.create); return; }
    if (o.item.kind === "tag") { setQ(`#${o.item.id}`); inputRef.current?.focus(); return; }
    const href = searchHref(o.item);
    if (href) onGo(href);
  };
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setActive((i) => Math.min(i + 1, Math.max(options.length - 1, 0))); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setActive((i) => Math.max(i - 1, 0)); }
    else if (e.key === "Enter") { e.preventDefault(); choose(options[active]); }
  };
  useEffect(() => {
    document.getElementById(`${listId}-${active}`)?.scrollIntoView({ block: "nearest" });
  }, [active, listId]);

  if (creating && access) {
    return <CreateForm kind={creating} access={access} initial={q.startsWith("#") ? "" : q} onBack={() => setCreating(null)} onGo={onGo} />;
  }

  const textMode = res?.mode === "text" || res?.mode === "tag";
  let lastGroup = "";
  return (
    <div className="flex flex-col">
      <DialogTitle className="sr-only">Pesquisar</DialogTitle>
      <DialogDescription className="sr-only">Pesquisa guiões, fontes, referências, tarefas, campanhas, pessoas e estilos. Setas para escolher, Enter para abrir.</DialogDescription>
      <div className="flex items-center gap-2 border-b px-3">
        <SearchIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
        <input
          ref={inputRef}
          autoFocus
          role="combobox"
          aria-expanded
          aria-controls={listId}
          aria-activedescendant={options.length ? `${listId}-${active}` : undefined}
          aria-label="Pesquisar"
          className="h-12 w-full bg-transparent text-base outline-none placeholder:text-muted-foreground sm:text-sm"
          placeholder="Pesquisa por título, #etiqueta ou ID"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={onKeyDown}
        />
        {loading && <Loader2Icon className="size-4 shrink-0 animate-spin text-muted-foreground" aria-label="A pesquisar" />}
      </div>
      {wsId && multi && (
        <div className="flex flex-wrap items-center gap-1 border-b px-3 py-2 text-xs" role="group" aria-label="Onde pesquisar">
          <Button size="xs" variant={onlyHere ? "secondary" : "ghost"} aria-pressed={onlyHere} onClick={() => setOnlyHere(true)}>Só {wsName ?? "este cliente"}</Button>
          <Button size="xs" variant={!onlyHere ? "secondary" : "ghost"} aria-pressed={!onlyHere} onClick={() => setOnlyHere(false)}>Todos os meus clientes</Button>
        </div>
      )}
      <div id={listId} role="listbox" aria-label="Resultados" className="max-h-[60vh] overflow-y-auto p-1">
        {err ? (
          <Alert variant="destructive" className="m-2 w-auto">
            <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
              <span>{err}</span>
              <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}>Tentar de novo</Button>
            </AlertDescription>
          </Alert>
        ) : !res ? (
          <div className="flex flex-col gap-2 p-2">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-9 w-full" />)}</div>
        ) : (
          <>
            {res.mode === "short" && <p className="px-3 py-4 text-sm text-muted-foreground">Escreve pelo menos 2 letras.</p>}
            {textMode && res.groups.length === 0 && !loading && (
              <div className="px-3 py-6 text-center text-sm">
                <p>Nada encontrado para «{res.q}».</p>
                <p className="mt-1 text-muted-foreground">Só aparece o que podes ver{onlyHere && wsId ? " neste cliente" : " nos teus clientes"}. Experimenta outra palavra, uma #etiqueta ou o ID.</p>
              </div>
            )}
            {res.mode === "suggestions" && res.groups.every((g) => g.items.length === 0) && creates.length === 0 && (
              <p className="px-3 py-6 text-center text-sm text-muted-foreground">Escreve para pesquisar em guiões, fontes, referências, tarefas, campanhas, pessoas e estilos.</p>
            )}
            {options.map((o, i) => {
              const head = o.group !== lastGroup ? o.group : null;
              lastGroup = o.group;
              const g = res.groups.find((x) => x.label === o.group);
              const lastOfGroup = options[i + 1]?.group !== o.group;
              const Icon = o.type === "create" ? CREATE_ICON[o.create] : KIND_ICON[o.item.kind] ?? SearchIcon;
              return (
                <div key={o.key}>
                  {head && <div className="px-2 pt-2 pb-1 text-xs font-medium text-muted-foreground" aria-hidden>{head}</div>}
                  <div
                    id={`${listId}-${i}`}
                    role="option"
                    data-type={o.type}
                    aria-selected={i === active}
                    onMouseMove={() => setActive(i)}
                    onClick={() => choose(o)}
                    className={cn("flex min-h-10 cursor-pointer items-center gap-3 rounded-md px-2 py-1.5", i === active && "bg-accent text-accent-foreground")}
                  >
                    <Icon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                    {o.type === "create" ? (
                      <span className="text-sm">{CREATE_LABEL[o.create]}{q && !q.startsWith("#") ? <span className="text-muted-foreground"> «{q}»</span> : null}</span>
                    ) : (
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm">{o.item.title}</div>
                        <div className="truncate text-xs text-muted-foreground">{subtitle(o.item)}</div>
                      </div>
                    )}
                    {o.type === "item" && o.item.ws_name && (multi || !onlyHere) && (
                      <span className="max-w-28 shrink-0 truncate rounded-full border px-2 py-0.5 text-xs text-muted-foreground">{o.item.ws_name}</span>
                    )}
                  </div>
                  {lastOfGroup && g?.more && <p className="px-2 pb-1 text-xs text-muted-foreground">Há mais: escreve mais palavras para afinar.</p>}
                </div>
              );
            })}
            {!actions && !wsId && res.mode === "suggestions" && (
              <p className="px-3 pt-2 pb-3 text-xs text-muted-foreground">Para criar fontes, guiões, campanhas ou tarefas, abre primeiro um cliente.</p>
            )}
          </>
        )}
      </div>
      <div className="hidden items-center gap-3 border-t px-3 py-2 text-xs text-muted-foreground sm:flex">
        <span><Kbd>↑</Kbd> <Kbd>↓</Kbd> escolher</span><span><Kbd>Enter</Kbd> abrir</span><span><Kbd>Esc</Kbd> fechar</span>
      </div>
    </div>
  );
}

function CreateForm({ kind, access, initial, onBack, onGo }: { kind: Create; access: Access; initial: string; onBack: () => void; onGo: (href: string) => void }) {
  const [v, setV] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const title = v.trim();
    if (!title) { setErr("Escreve um título."); return; }
    setBusy(true); setErr("");
    try {
      if (kind === "script") {
        const d = todayDubai();
        const g = await createContent(access, { date: d, tema: title, corpo: "Escreve aqui o corpo do guião.", hooks: [{ text: "", mecanismo: "" }] });
        onGo(clientPath(access.ws, `/guioes?date=${g.date}&open=${encodeURIComponent(g.id)}`));
      } else if (kind === "source") {
        await createSource(access, { titulo: title });
        onGo(clientPath(access.ws, `/fontes?q=${encodeURIComponent(title)}`));
      } else if (kind === "project") {
        const r = await saveProject(access, null, { name: title, kind: "campanha" });
        const p = r.projects.find((x) => x.name.trim().toLowerCase() === title.toLowerCase());
        onGo(clientPath(access.ws, p ? `/guioes?campanha=${p.id}` : "/guioes"));
      } else {
        const t = await createTask(access, { title });
        onGo(clientPath(access.ws, `/tarefas?task=${t.id}`));
      }
    } catch (e2) {
      const dup = kind === "source" ? duplicateOf(e2) : null;
      setErr(dup ? "Esta fonte já existe neste cliente." : (e2 as Error).message);
      setBusy(false);
    }
  };
  return (
    <form onSubmit={submit} className="flex flex-col gap-3 p-4">
      <DialogTitle>{CREATE_LABEL[kind]}</DialogTitle>
      <DialogDescription>
        {kind === "script" ? "Fica em rascunho para hoje; depois escreves o corpo e os hooks." : kind === "task" ? "Fica por atribuir; depois escolhes responsável e prazo." : "Podes completar os outros campos a seguir."}
      </DialogDescription>
      <label className="flex flex-col gap-1 text-sm">
        <span>{CREATE_FIELD[kind]}</span>
        <Input autoFocus value={v} maxLength={kind === "project" ? 80 : 200} onChange={(e) => setV(e.target.value)} aria-invalid={!!err} />
      </label>
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      <div className="flex justify-between gap-2">
        <Button type="button" variant="ghost" size="sm" onClick={onBack} disabled={busy}><ArrowLeftIcon /> Voltar</Button>
        <Button type="submit" size="sm" disabled={busy}>{busy ? <Loader2Icon className="animate-spin" /> : <PlusIcon />} Criar</Button>
      </div>
    </form>
  );
}
