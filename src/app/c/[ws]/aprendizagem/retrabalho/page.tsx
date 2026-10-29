"use client";

import { useState } from "react";
import { Loader2Icon, PlusIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { Bar, LearnState, Stat, selectCls, useLoad } from "@/components/learn/learn-shared";
import type { Access } from "@/lib/access";
import {
  fetchReworkDashboard, fetchReworkReasons, hours, monthLabel, pct, saveReworkReason, seedReworkReasons,
  type ReworkReason, type ReworkReasonList, type ReworkStage,
} from "@/lib/learn";

/*
 * Retrabalho por etapa (FR-17-10, ADR-0037): pedidos de alterações e rejeições por motivo, taxa de retrabalho e tempo
 * perdido, por mês no fuso do cliente. Em teste: flag learn.rework. O servidor verifica learn.read em cada pedido.
 */

export default function RetrabalhoPage() {
  return (
    <WorkspaceGate need="learn.read">
      {(access) => <FlagGate flag="learn.rework" ws={access.ws}><ReworkView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

function ReworkView({ access }: { access: Access }) {
  const [months, setMonths] = useState(6);
  const dash = useLoad(() => fetchReworkDashboard(access, months), `${access.ws}:${months}`);
  const d = dash.data;
  const maxReason = Math.max(1, ...(d?.by_reason ?? []).map((r) => r.changes + r.rejected));
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Retrabalho</h1>
          <p className="text-sm text-muted-foreground">
            Pedidos de alterações e rejeições por motivo, quanto do que se revê volta para trás e quanto tempo se perde até voltar a revisão.
            Os relatórios não mudam prompts nem regras sozinhos.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <label className="flex items-center gap-2 text-sm">Período
            <select className={selectCls} value={months} onChange={(e) => setMonths(Number(e.target.value))}>
              <option value={3}>3 meses</option><option value={6}>6 meses</option><option value={12}>12 meses</option>
            </select>
          </label>
          <Button size="sm" variant="outline" onClick={dash.reload}><RotateCwIcon /> Atualizar</Button>
        </div>
      </div>
      <LearnState loading={dash.loading} error={dash.error} reload={dash.reload} label="o retrabalho" forbidden="Não tens acesso ao retrabalho deste cliente.">
        {d && (
          <>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
              <Stat label="Decisões de revisão" value={d.totals.decisions} />
              <Stat label="Taxa de retrabalho" value={pct(d.totals.rework_rate)} hint="alterações + rejeições ÷ decisões" />
              <Stat label="Tempo perdido" value={hours(d.totals.hours_lost)} hint="do pedido até voltar a revisão" />
              <Stat label="Em aberto" value={d.totals.cycles_open} hint="pedidos de alterações por responder" />
              <Stat label="Sem categoria" value={d.totals.uncategorized} hint="antes da taxonomia ou sem flag" />
            </div>
            <div className="flex flex-wrap gap-2" aria-label="Etapas">
              {d.stages.map((s) => (
                <Badge key={s.key} variant={s.available ? "default" : "outline"} title={s.reason}>
                  {s.label}{s.available ? "" : ": indisponível"}
                </Badge>
              ))}
            </div>
            {d.stages.filter((s) => !s.available).map((s) => <p key={s.key} className="text-xs text-muted-foreground">{s.label}: {s.reason}</p>)}
            {d.totals.decisions === 0 ? (
              <Alert><AlertDescription>Ainda não há decisões de revisão neste período.</AlertDescription></Alert>
            ) : (
              <div className="grid gap-4 lg:grid-cols-2">
                <WidgetBoundary label="retrabalho por mês">
                  <Card>
                    <CardHeader><CardTitle>Por mês · guião</CardTitle><CardDescription>Fuso do cliente ({d.timezone}).</CardDescription></CardHeader>
                    <CardContent className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow>
                          <TableHead>Mês</TableHead><TableHead className="text-right">Decisões</TableHead><TableHead className="text-right">Alterações</TableHead>
                          <TableHead className="text-right">Rejeições</TableHead><TableHead className="text-right">Taxa</TableHead><TableHead className="text-right">Tempo perdido</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {d.by_month.map((m) => (
                            <TableRow key={m.month}>
                              <TableCell>{monthLabel(m.month)}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.decisions}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.changes}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.rejected}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.decisions ? pct(m.rework_rate) : "-"}</TableCell>
                              <TableCell className="text-right tabular-nums">
                                {m.cycles_closed ? hours(m.hours_lost) : "-"}
                                {m.hours_median !== null && <span className="block text-xs text-muted-foreground">mediana {hours(m.hours_median)}</span>}
                                {m.cycles_open > 0 && <span className="block text-xs text-muted-foreground">{m.cycles_open} em aberto</span>}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </CardContent>
                  </Card>
                </WidgetBoundary>
                <WidgetBoundary label="retrabalho por motivo">
                  <Card>
                    <CardHeader><CardTitle>Por motivo</CardTitle><CardDescription>Todo o período escolhido.</CardDescription></CardHeader>
                    <CardContent className="flex flex-col gap-3">
                      {d.by_reason.length === 0 && <p className="text-sm text-muted-foreground">Sem pedidos de alterações nem rejeições.</p>}
                      {d.by_reason.map((r) => (
                        <div key={r.code} className="flex flex-col gap-1 text-sm">
                          <div className="flex flex-wrap justify-between gap-2">
                            <span className="font-medium">{r.label}</span>
                            <span className="text-xs text-muted-foreground">{r.changes} alterações · {r.rejected} rejeições · {hours(r.hours_lost)} perdidas</span>
                          </div>
                          <Bar value={r.changes + r.rejected} max={maxReason} label={`${r.label}: ${r.changes + r.rejected}`} />
                        </div>
                      ))}
                    </CardContent>
                  </Card>
                </WidgetBoundary>
              </div>
            )}
          </>
        )}
      </LearnState>
      <WidgetBoundary label="motivos"><ReasonsCard access={access} onChange={dash.reload} /></WidgetBoundary>
    </div>
  );
}

const STAGES: { v: ReworkStage; l: string }[] = [{ v: "guiao", l: "Guião" }, { v: "video", l: "Vídeo" }];

function ReasonsCard({ access, onChange }: { access: Access; onChange: () => void }) {
  const list = useLoad(() => fetchReworkReasons(access), access.ws);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [code, setCode] = useState("");
  const [label, setLabel] = useState("");
  const [stages, setStages] = useState<ReworkStage[]>(["guiao"]);
  const l = list.data;
  const act = async (f: () => Promise<ReworkReasonList>) => {
    setBusy(true); setErr("");
    try { list.setData(await f()); onChange(); return true; } catch (e) { setErr((e as Error).message); return false; } finally { setBusy(false); }
  };
  return (
    <Card>
      <CardHeader>
        <CardTitle>Motivos deste cliente</CardTitle>
        <CardDescription>A lista que aparece ao rejeitar ou pedir alterações. O código não muda depois de criado; desativar tira da escolha sem perder o histórico.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <LearnState loading={list.loading} error={list.error} reload={list.reload} label="os motivos" forbidden="Não tens acesso aos motivos deste cliente.">
          {l && (
            <>
              {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
              {l.reasons.length === 0 && (
                <div className="flex flex-col items-start gap-2 rounded-lg border border-dashed p-4 text-sm">
                  <p>Ainda não há motivos. Sem motivos, rejeitar continua só com o texto.</p>
                  {l.can_manage
                    ? <Button size="sm" disabled={busy} onClick={() => void act(() => seedReworkReasons(access))}>{busy && <Loader2Icon className="animate-spin" />}Começar pela lista sugerida</Button>
                    : <p className="text-muted-foreground">Quem gere a aprendizagem deste cliente pode criá-los.</p>}
                </div>
              )}
              {l.reasons.length > 0 && (
                <ul className="flex flex-col divide-y rounded-lg border">
                  {l.reasons.map((r) => <ReasonRow key={r.id} r={r} canManage={l.can_manage} busy={busy}
                    onSave={(f) => act(() => saveReworkReason(access, r.id, f))} />)}
                </ul>
              )}
              {l.can_manage && l.reasons.length > 0 && (
                <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => {
                  e.preventDefault();
                  if (await act(() => saveReworkReason(access, null, { code: code.trim(), label: label.trim(), applies_to: stages }))) { setCode(""); setLabel(""); }
                }}>
                  <label className="flex flex-col gap-1 text-xs">Código
                    <Input className="h-8 w-32" value={code} maxLength={40} placeholder="ex.: legendas" onChange={(e) => setCode(e.target.value.toLowerCase())} />
                  </label>
                  <label className="flex min-w-[10rem] flex-1 flex-col gap-1 text-xs">Nome
                    <Input className="h-8" value={label} maxLength={60} placeholder="Como aparece na escolha" onChange={(e) => setLabel(e.target.value)} />
                  </label>
                  <fieldset className="flex items-center gap-3 text-sm">
                    <legend className="sr-only">Etapas</legend>
                    {STAGES.map((s) => (
                      <label key={s.v} className="flex items-center gap-1.5">
                        <input type="checkbox" checked={stages.includes(s.v)} onChange={(e) => setStages((x) => (e.target.checked ? [...x, s.v] : x.filter((y) => y !== s.v)))} />{s.l}
                      </label>
                    ))}
                  </fieldset>
                  <Button size="sm" type="submit" disabled={busy || code.trim().length < 2 || label.trim().length < 2 || stages.length === 0}><PlusIcon />Motivo novo</Button>
                </form>
              )}
            </>
          )}
        </LearnState>
      </CardContent>
    </Card>
  );
}

function ReasonRow({ r, canManage, busy, onSave }: { r: ReworkReason; canManage: boolean; busy: boolean; onSave: (f: Partial<ReworkReason>) => Promise<boolean> }) {
  const [label, setLabel] = useState(r.label);
  return (
    <li className="flex flex-wrap items-center gap-2 p-2 text-sm">
      <code className="w-28 truncate text-xs text-muted-foreground">{r.code}</code>
      {canManage
        ? <Input aria-label={`Nome do motivo ${r.code}`} className="h-8 min-w-[10rem] flex-1" value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)}
            onBlur={() => { if (label.trim() && label.trim() !== r.label) void onSave({ label: label.trim() }); }} />
        : <span className="flex-1">{r.label}</span>}
      <span className="flex gap-1">{r.applies_to.map((s) => <Badge key={s} variant="outline">{s === "guiao" ? "Guião" : "Vídeo"}</Badge>)}</span>
      <span className="w-16 text-right text-xs text-muted-foreground tabular-nums">{r.uses} usos</span>
      {canManage
        ? <Button size="sm" variant="ghost" disabled={busy} onClick={() => void onSave({ active: !r.active })}>{r.active ? "Desativar" : "Ativar"}</Button>
        : !r.active && <Badge variant="outline">inativo</Badge>}
    </li>
  );
}
