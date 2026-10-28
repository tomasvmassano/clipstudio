"use client";

import { Suspense, useMemo, useState } from "react";
import Link from "next/link";
import { DownloadIcon, MonitorPlayIcon } from "lucide-react";
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
import { splitDay, teleprompterText, todayDubai, tpQueue, words } from "@/lib/data";
import { WPS } from "@/lib/types";

type Filter = "todos" | "por_validar" | "validados" | "rejeitados" | "gravados";

function Stat({ v, l }: { v: string | number; l: string }) {
  return (
    <div className="flex items-baseline gap-1.5 rounded-full border bg-background px-3 py-1 text-sm">
      <b className="tabular-nums">{v}</b>
      <span className="text-muted-foreground">{l}</span>
    </div>
  );
}

function GuioesInner({ access }: { access: Access }) {
  const [date, setDate] = useState(todayDubai());
  const [filter, setFilter] = useState<Filter>("todos");
  const [msg, setMsg] = useState("");
  const { all, loading, error, patch, caps, canWrite } = useGuioes(access, date);
  const { day, carry } = useMemo(() => splitDay(all, date), [all, date]);
  const isToday = date === todayDubai();

  const ok = day.filter((g) => g.status !== "rejeitado");
  const stats = {
    para: ok.length,
    val: ok.filter((g) => g.validado).length,
    grav: ok.filter((g) => g.gravado).length,
    rej: day.length - ok.length,
    min: Math.round(ok.reduce((t, g) => t + (words(g.corpo) + words(g.hooks[0]?.text)) / WPS, 0) / 60),
  };

  const shown = day.filter((g) => {
    if (filter === "por_validar") return g.status !== "rejeitado" && !g.validado;
    if (filter === "validados") return g.validado && g.status !== "rejeitado";
    if (filter === "rejeitados") return g.status === "rejeitado";
    if (filter === "gravados") return g.gravado;
    return true;
  });

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
          {caps.export && <Button size="sm" variant="outline" onClick={exportTxt}><DownloadIcon /> Exportar .txt</Button>}
          <Button size="sm" render={<Link href={`/teleprompter?date=${date}`} />} nativeButton={false}><MonitorPlayIcon /> Teleprompter</Button>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <Stat v={stats.para} l="para gravar" />
        <Stat v={`${stats.val}/${stats.para}`} l="validados" />
        <Stat v={stats.grav} l="gravados" />
        <Stat v={stats.rej} l="rejeitados" />
        <Stat v={`${stats.min} min`} l="de texto" />
        {isToday && carry.length > 0 && <Stat v={carry.length} l="por gravar de dias anteriores" />}
      </div>

      {!canWrite && (
        <Alert>
          <AlertDescription>
            Tens acesso de leitura neste workspace: podes ler e abrir o teleprompter, mas não validar, editar nem rejeitar.
          </AlertDescription>
        </Alert>
      )}
      {canWrite && (
        <Alert>
          <AlertDescription>
            <b>Como validar:</b> lê cada guião e carrega em <i>Validar</i> nos que gravas tal como estão{caps.edit ? <>, <i>Editar</i> para mudar uma frase</> : null}{caps.reject ? <>, <i>Rejeitar</i> (com o motivo) nos que não dirias</> : null}. O teleprompter leva todos os que não rejeitaste.
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
        <ToggleGroupItem value="por_validar">Por validar</ToggleGroupItem>
        <ToggleGroupItem value="validados">Validados</ToggleGroupItem>
        <ToggleGroupItem value="gravados">Gravados</ToggleGroupItem>
        <ToggleGroupItem value="rejeitados">Rejeitados</ToggleGroupItem>
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
          {isToday && filter === "todos" && carry.map((g) => <GuiaoCard key={g.id} g={g} carried caps={caps} onPatch={patch} onError={setMsg} />)}
          {shown.map((g) => <GuiaoCard key={g.id} g={g} caps={caps} onPatch={patch} onError={setMsg} />)}
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
