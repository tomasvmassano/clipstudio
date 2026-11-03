"use client";

import { WsLink } from "@/components/ws-link";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { DownloadIcon, ListChecksIcon, Loader2Icon, MonitorPlayIcon, PlusIcon, XIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { DayNav } from "@/components/day-nav";
import { GuiaoCard } from "@/components/guiao-card";
import { TeamCode } from "@/components/team-code";
import { useGuioes } from "@/components/use-guioes";
import { WorkspaceGate } from "@/components/workspace-gate";
import { GuioesBulkBar } from "@/components/guioes-bulk";
import { useSession } from "@/components/session-provider";
import { useFlags } from "@/lib/flags";
import { fetchProjects } from "@/lib/projects";
import type { Access } from "@/lib/access";
import { recordable, splitDay, teleprompterText, todayDubai, tpQueue, words } from "@/lib/data";
import { WPS, type Guiao } from "@/lib/types";

type Filter = "todos" | "rever" | "aprovados" | "gravados" | "rejeitados" | "arquivados";

function Stat({ v, l }: { v: string | number; l: string }) {
  return (
    <div className="flex items-baseline gap-1.5 rounded-full border bg-background px-3 py-1 text-sm">
      <b className="tabular-nums">{v}</b>
      <span className="text-muted-foreground">{l}</span>
    </div>
  );
}

function GuioesInner({ access }: { access: Access }) {
  const params = useSearchParams();
  const [date, setDate] = useState(() => (/^\d{4}-\d{2}-\d{2}$/.test(params.get("date") ?? "") ? params.get("date")! : todayDubai()));
  const [filter, setFilter] = useState<Filter>("todos");
  const [msg, setMsg] = useState("");
  const [creating, setCreating] = useState(false);
  const [fresh, setFresh] = useState<string | null>(null);
  const { all, loading, error, actions, create, caps, canWrite, reload } = useGuioes(access, date);
  const { can } = useSession();
  // operações em lote (FR-17-07): só com a flag guioes.bulk ligada; o servidor volta a verificar cada ação
  const flags = useFlags(access.ws, access.token);
  const bulkOn = !!flags?.has("guioes.bulk");
  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  // ?campanha=<id> (vindo da pesquisa global): mostra só os guiões dessa campanha
  const campanha = params.get("campanha");
  const [campanhaOn, setCampanhaOn] = useState(true);
  const [campanhaName, setCampanhaName] = useState<string | null>(null);
  useEffect(() => {
    if (!campanha) return;
    let alive = true;
    fetchProjects(access).then((l) => { if (alive) setCampanhaName(l.projects.find((p) => p.id === campanha)?.name ?? "campanha desconhecida"); }).catch(() => {});
    return () => { alive = false; };
  }, [access, campanha]);
  const byCampanha = campanha && campanhaOn ? campanha : null;
  const { day, carry } = useMemo(() => splitDay(all, date), [all, date]);
  const isToday = date === todayDubai();
  // ?open=<id> (vindo da caixa ou da minha fila): leva ao guião e destaca-o
  const openId = params.get("open");
  useEffect(() => {
    if (loading || !openId) return;
    const el = document.querySelector<HTMLElement>(`[data-guiao="${CSS.escape(openId)}"]`);
    if (!el) return;
    el.scrollIntoView({ block: "center" });
    el.classList.add("ring-2", "ring-primary");
    const t = setTimeout(() => el.classList.remove("ring-2", "ring-primary"), 4000);
    return () => clearTimeout(t);
  }, [loading, openId]);

  const ok = day.filter(recordable);
  const toReview = (s: string) => s === "in_review" || s === "draft" || s === "changes_requested";
  const stats = {
    para: ok.length,
    val: ok.filter((g) => g.editorial_status === "approved").length,
    rever: ok.filter((g) => toReview(g.editorial_status)).length,
    grav: ok.filter((g) => ["recorded", "editing", "ready", "published"].includes(g.production_status)).length,
    rej: day.filter((g) => g.editorial_status === "rejected").length,
    min: Math.round(ok.reduce((t, g) => t + (words(g.corpo) + words(g.hooks[0]?.text)) / WPS, 0) / 60),
  };

  const shown = day.filter((g) => !byCampanha || g.project_id === byCampanha).filter((g) => {
    if (filter === "rever") return toReview(g.editorial_status);
    if (filter === "aprovados") return g.editorial_status === "approved";
    if (filter === "rejeitados") return g.editorial_status === "rejected";
    if (filter === "arquivados") return g.editorial_status === "archived";
    if (filter === "gravados") return ["recorded", "editing", "ready", "published"].includes(g.production_status);
    return g.editorial_status !== "archived";
  });

  const visibleIds = [...(isToday && filter === "todos" && !byCampanha ? carry : []), ...shown].map((g) => g.id);
  const selectedIds = visibleIds.filter((id) => selected.has(id));
  const toggle = (id: string) => setSelected((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const stopSelecting = () => { setSelecting(false); setSelected(new Set()); };
  const pick = (g: Guiao, card: React.ReactNode) => !selecting ? card : (
    <div key={g.id} className="flex items-start gap-2">
      <input type="checkbox" className="mt-4 size-5 shrink-0 accent-primary" checked={selected.has(g.id)} onChange={() => toggle(g.id)}
             aria-label={`Selecionar guião ${g.n}${g.tema ? `: ${g.tema}` : ""}`} />
      <div className="min-w-0 flex-1">{card}</div>
    </div>
  );

  const newScript = async () => {
    setCreating(true); setMsg("");
    try { const g = await create(date); setFresh(g.id); setFilter("todos"); }
    catch (e) { setMsg((e as Error).message); }
    finally { setCreating(false); }
  };

  const exportTxt = () => {
    const txt = teleprompterText(tpQueue(all, date));
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([txt], { type: "text/plain" }));
    a.download = `teleprompter-${date}.txt`;
    a.click();
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-4">
          <h1 className="text-2xl font-semibold tracking-tight">Guiões</h1>
          <DayNav date={date} onChange={setDate} />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <TeamCode />
          {caps.create && (
            <Button size="sm" variant="outline" disabled={creating} onClick={newScript}>
              {creating ? <Loader2Icon className="animate-spin" /> : <PlusIcon />} Novo guião
            </Button>
          )}
          {caps.export && <Button size="sm" variant="outline" onClick={exportTxt}><DownloadIcon /> Exportar .txt</Button>}
          {bulkOn && !selecting && <Button size="sm" variant="outline" onClick={() => setSelecting(true)}><ListChecksIcon /> Selecionar</Button>}
          <Button size="sm" render={<WsLink href={`/teleprompter?date=${date}`} />} nativeButton={false}><MonitorPlayIcon /> Teleprompter</Button>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <Stat v={stats.para} l="para gravar" />
        <Stat v={`${stats.val}/${stats.para}`} l="aprovados" />
        <Stat v={stats.rever} l="por rever" />
        <Stat v={stats.grav} l="gravados" />
        <Stat v={stats.rej} l="rejeitados" />
        <Stat v={`${stats.min} min`} l="de texto" />
        {isToday && carry.length > 0 && <Stat v={carry.length} l="por gravar de dias anteriores" />}
      </div>

      {!canWrite && (
        <Alert>
          <AlertDescription>
            Tens acesso de leitura neste workspace: podes ler e abrir o teleprompter, mas não aprovar, editar nem rejeitar.
          </AlertDescription>
        </Alert>
      )}
      {canWrite && (
        <Alert>
          <AlertDescription>
            <b>Como rever:</b> lê cada guião e carrega em <i>Aprovar</i> nos que gravas tal como estão{caps.edit ? <>, <i>Editar</i> para mudar uma frase (guarda sozinho)</> : null}{caps.reject ? <>, <i>Pedir alterações</i> ou <i>Rejeitar</i> com o motivo</> : null}. Cada aprovação fica presa à versão exata que aprovaste; o <i>Histórico</i> mostra todas. O teleprompter leva tudo o que não foi rejeitado nem arquivado.
          </AlertDescription>
        </Alert>
      )}
      {(msg || error) && (
        <Alert variant="destructive">
          <AlertDescription>{msg || error}</AlertDescription>
        </Alert>
      )}

      {campanha && (
        <div className="flex flex-wrap items-center gap-2 text-sm">
          {campanhaOn ? (
            <span className="flex items-center gap-1 rounded-full border px-3 py-1">
              Campanha: <b>{campanhaName ?? "…"}</b> (neste dia)
              <Button size="icon-xs" variant="ghost" aria-label="Mostrar todas as campanhas" onClick={() => setCampanhaOn(false)}><XIcon /></Button>
            </span>
          ) : <Button size="sm" variant="ghost" onClick={() => setCampanhaOn(true)}>Mostrar só a campanha {campanhaName ?? ""}</Button>}
        </div>
      )}

      {bulkOn && selecting && (
        <GuioesBulkBar
          access={access}
          selected={selectedIds}
          rows={all}
          caps={{ edit: caps.edit, approve: caps.approve, schedule: can("calendar.schedule"), export: caps.export }}
          allSelected={visibleIds.length > 0 && selectedIds.length === visibleIds.length}
          onSelectAll={() => setSelected(new Set(visibleIds))}
          onClear={stopSelecting}
          onDone={async () => { setSelected(new Set()); await reload(); }}
        />
      )}

      <ToggleGroup value={[filter]} onValueChange={(v) => setFilter(((v as string[])[0] as Filter) ?? "todos")} variant="outline" size="sm">
        <ToggleGroupItem value="todos">Todos</ToggleGroupItem>
        <ToggleGroupItem value="rever">Por rever</ToggleGroupItem>
        <ToggleGroupItem value="aprovados">Aprovados</ToggleGroupItem>
        <ToggleGroupItem value="gravados">Gravados</ToggleGroupItem>
        <ToggleGroupItem value="rejeitados">Rejeitados</ToggleGroupItem>
        {caps.archive && <ToggleGroupItem value="arquivados">Arquivados</ToggleGroupItem>}
      </ToggleGroup>

      {loading ? (
        <div className="flex flex-col gap-3">
          {[1, 2, 3].map((i) => <Skeleton key={i} className="h-40 w-full" />)}
        </div>
      ) : day.length === 0 && carry.length === 0 ? (
        <Alert>
          <AlertDescription>Ainda não há guiões para este dia. Os guiões do motor aparecem aqui quando a corrida do dia acaba.</AlertDescription>
        </Alert>
      ) : (
        <div className="flex flex-col gap-3">
          {isToday && filter === "todos" && !byCampanha && carry.map((g) => pick(g, <GuiaoCard key={g.id} g={g} carried caps={caps} actions={actions} onError={setMsg} />))}
          {shown.map((g) => pick(g, <GuiaoCard key={g.id} g={g} caps={caps} actions={actions} onError={setMsg} startInEdit={g.id === fresh} />))}
          {byCampanha && shown.length === 0 && (
            <Alert><AlertDescription>Nenhum guião desta campanha neste dia{filter !== "todos" ? " com este filtro" : ""}. Muda de dia ou tira o filtro da campanha.</AlertDescription></Alert>
          )}
        </div>
      )}
    </div>
  );
}

export default function GuioesPage() {
  return (
    <Suspense fallback={<Skeleton className="h-40 w-full" />}>
      <WorkspaceGate need="scripts.read">{(access) => <GuioesInner access={access} />}</WorkspaceGate>
    </Suspense>
  );
}
