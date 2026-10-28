"use client";

import Link from "next/link";
import { useMemo } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { TeamCode } from "@/components/team-code";
import { useGuioes } from "@/components/use-guioes";
import { niceDate, splitDay, todayDubai } from "@/lib/data";
import { cn } from "@/lib/utils";

function Stage({ label, value, sub, later }: { label: string; value: string; sub?: string; later?: boolean }) {
  return (
    <Card className={cn(later && "border-dashed opacity-60")}>
      <CardContent className="p-4">
        <div className="text-xs text-muted-foreground">{label}</div>
        <div className="mt-1 text-xl font-semibold tabular-nums">{value}</div>
        {sub && <div className="text-xs text-muted-foreground">{sub}</div>}
      </CardContent>
    </Card>
  );
}

export default function Hoje() {
  const date = todayDubai();
  const { all, loading } = useGuioes(date);
  const { day, carry } = useMemo(() => splitDay(all, date), [all, date]);
  const ok = day.filter((g) => g.status !== "rejeitado");
  const val = ok.filter((g) => g.validado).length;
  const grav = ok.filter((g) => g.gravado).length;
  const rej = day.filter((g) => g.status === "rejeitado");
  const target = 30;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Hoje</h1>
          <p className="text-sm text-muted-foreground">{niceDate(date)} · hora de Dubai</p>
        </div>
        <TeamCode />
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Stage label="Guiões" value={loading ? "…" : `${ok.length} / ${target}`} sub={rej.length ? `${rej.length} rejeitados` : undefined} />
        <Stage label="Validados" value={loading ? "…" : `${val} / ${ok.length}`} sub="pelo Creator" />
        <Stage label="Gravados" value={loading ? "…" : `${grav} / ${ok.length}`} sub={carry.length ? `${carry.length} por gravar de dias anteriores` : undefined} />
        <Stage label="Edição" value="—" sub="v1" later />
        <Stage label="Revisão" value="—" sub="v1" later />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardContent className="flex flex-col gap-3 p-4">
            <h2 className="font-medium">Validação de hoje</h2>
            <Progress value={ok.length ? (val / ok.length) * 100 : 0} />
            <p className="text-sm text-muted-foreground">{val} de {ok.length} guiões validados. {val < ok.length ? `Faltam ${ok.length - val}.` : "Pronto para gravar."}</p>
            <div className="flex gap-2">
              <Button size="sm" render={<Link href="/guioes" />} nativeButton={false}>Abrir guiões</Button>
              <Button size="sm" variant="outline" render={<Link href="/teleprompter" />} nativeButton={false}>Teleprompter</Button>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex flex-col gap-2 p-4">
            <h2 className="font-medium">O que pede atenção</h2>
            <ul className="space-y-1.5 text-sm">
              <li className="flex justify-between"><span>Guiões rejeitados pelo Creator</span><b className="tabular-nums">{rej.length}</b></li>
              <li className="flex justify-between"><span>Por validar</span><b className="tabular-nums">{ok.length - val}</b></li>
              <li className="flex justify-between"><span>Por gravar de dias anteriores</span><b className="tabular-nums">{carry.length}</b></li>
            </ul>
            {rej.length > 0 && (
              <ul className="mt-2 space-y-1 border-t pt-2 text-xs text-muted-foreground">
                {rej.slice(0, 5).map((g) => <li key={g.id}>#{g.n} {g.tema}: {g.motivo_rejeicao}</li>)}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
