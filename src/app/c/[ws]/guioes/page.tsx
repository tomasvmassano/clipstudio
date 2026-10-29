"use client";

import { WsLink } from "@/components/ws-link";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { DownloadIcon, Loader2Icon, MonitorPlayIcon, PlusIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { DayNav } from "@/components/day-nav";
import { GuiaoCard } from "@/components/guiao-card";
import { TeamCode } from "@/components/team-code";
import { useGuioes } from "@/components/use-guioes";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { recordable, splitDay, teleprompterText, todayDubai, tpQueue, words } from "@/lib/data";
import { WPS } from "@/lib/types";

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
  const { all, loading, error, actions, create, caps, canWrite } = useGuioes(access, date);
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

  const shown = day.filter((g) => {
    if (filter === "rever") return toReview(g.editorial_status);
    if (filter === "aprovados") return g.editorial_status === "approved";
    if (filter === "rejeitados") return g.editorial_status === "rejected";
    if (filter === "arquivados") return g.editorial_status === "archived";
    if (filter === "gravados") return ["recorded", "editing", "ready", "published"].includes(g.production_status);
    return g.editorial_status !== "archived";
  });

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
          {isToday && filter === "todos" && carry.map((g) => <GuiaoCard key={g.id} g={g} carried caps={caps} actions={actions} onError={setMsg} />)}
          {shown.map((g) => <GuiaoCard key={g.id} g={g} caps={caps} actions={actions} onError={setMsg} startInEdit={g.id === fresh} />)}
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
