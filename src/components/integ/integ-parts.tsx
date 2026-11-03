"use client";

import { useState, type ReactNode } from "react";
import { CheckCircle2Icon, CircleDashedIcon, Loader2Icon, RotateCwIcon, TriangleAlertIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import type { Access } from "@/lib/access";
import { HEALTH_CLASS, JOB_STATUS_LABEL, OUTCOME_LABEL, ago, expiryText, reasonOk, stateLabel, type IntegHealth } from "@/lib/integ-format";
import {
  isFlagOff, isForbidden, revokeSocialAccount, testIntegration,
  type IntegAction, type IntegCheck, type IntegItem, type PlatformLimit, type ScrapingAccount, type SocialAccount,
} from "@/lib/integrations";
import { dateTime } from "@/lib/perf-format";

/** Estados de uma leitura: a carregar, sem acesso, desligado, erro com "tentar de novo". */
export function IntegState({ loading, error, reload, forbidden, children }: {
  loading: boolean; error: unknown; reload: () => void; forbidden: string; children: ReactNode;
}) {
  if (error) {
    if (isForbidden(error)) return <Alert><AlertDescription>{forbidden}</AlertDescription></Alert>;
    if (isFlagOff(error)) return <Alert><AlertDescription>{(error as Error).message}</AlertDescription></Alert>;
    return (
      <Alert variant="destructive" role="alert">
        <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
          <span>Não consegui carregar as integrações: {(error as Error).message}</span>
          <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
        </AlertDescription>
      </Alert>
    );
  }
  if (loading) {
    return (
      <div className="grid gap-3 md:grid-cols-2" aria-busy="true" aria-label="A carregar as integrações">
        {Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-40" />)}
      </div>
    );
  }
  return <>{children}</>;
}

const HEALTH_ICON: Record<IntegHealth, ReactNode> = {
  ok: <CheckCircle2Icon aria-hidden className="size-4" />,
  aviso: <TriangleAlertIcon aria-hidden className="size-4" />,
  indisponivel: <CircleDashedIcon aria-hidden className="size-4" />,
};
const healthOf = (state: string): IntegHealth =>
  ["ligada", "em_dia", "ativo"].includes(state) ? "ok"
    : ["a_expirar", "atrasada", "parado", "expirada", "parcial"].includes(state) ? "aviso" : "indisponivel";

/** Estado com ícone e texto (a cor nunca carrega significado sozinha). */
export function StateBadge({ state, health }: { state: string; health?: IntegHealth }) {
  const h = health ?? healthOf(state);
  return (
    <span className={`inline-flex items-center gap-1 text-sm font-medium ${HEALTH_CLASS[h]}`} data-state={state}>
      {HEALTH_ICON[h]}{stateLabel(state)}
    </span>
  );
}

export function UnavailableActions({ actions }: { actions: IntegAction[] }) {
  const off = actions.filter((a) => !a.available && a.key !== "revogar" && a.key !== "testar");
  if (off.length === 0) return null;
  return (
    <ul className="flex flex-col gap-1 text-xs text-muted-foreground" aria-label="Ações indisponíveis">
      {off.map((a) => <li key={a.key} data-action-off={a.key}><span className="font-medium text-foreground">{a.label}: indisponível.</span> {a.reason}</li>)}
    </ul>
  );
}

function limitText(l: PlatformLimit) {
  const per = l.scope === "conta" ? (l.window_kind === "rolling_24h" ? "por conta em 24 h móveis" : "por conta por dia") : "por dia no projeto da agência";
  return `${l.max_posts} ${per}`;
}
export function LimitLine({ l }: { l: PlatformLimit }) {
  return (
    <p className="text-xs text-muted-foreground">
      <span className="font-medium text-foreground">Limite da API:</span> {limitText(l)} (verificado a {new Date(l.verified_on).toLocaleDateString("pt-PT")}).
      {l.public_requires_audit ? " Só público depois da auditoria da plataforma." : ""}
    </p>
  );
}

/** Um cartão por integração do cliente. */
export function IntegCard({ item, access, tz, canManage, onChanged }: {
  item: IntegItem; access: Access; tz: string; canManage: boolean; onChanged: () => void;
}) {
  const test = item.actions.find((a) => a.key === "testar");
  return (
    <Card className="flex flex-col" data-integration={item.key}>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <CardTitle className="text-base">{item.label}</CardTitle>
          <StateBadge state={item.state} health={item.health} />
        </div>
        <CardDescription>{item.provides}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col gap-3 text-sm">
        {item.kind === "social" && <SocialDetail item={item} access={access} tz={tz} onChanged={onChanged} />}
        {item.kind === "scraping" && <ScrapingDetail item={item} tz={tz} />}
        {item.kind === "worker" && <WorkerDetail item={item} tz={tz} />}
        {item.blocked_reason && <p className="text-xs text-muted-foreground">{item.blocked_reason}</p>}
        {item.missing && <p className="text-xs text-muted-foreground"><span className="font-medium text-foreground">O que falta:</span> {item.missing}</p>}
        <UnavailableActions actions={item.actions} />
        <p className="text-xs text-muted-foreground"><span className="font-medium text-foreground">Estado vem de:</span> {item.state_source}</p>
        {test && <TestRow item={item} action={test} access={access} tz={tz} canManage={canManage} onChanged={onChanged} />}
      </CardContent>
    </Card>
  );
}

function SocialDetail({ item, access, tz, onChanged }: { item: IntegItem; access: Access; tz: string; onChanged: () => void }) {
  const accounts = (item.detail.accounts ?? []) as SocialAccount[];
  const lim = item.detail.limits as PlatformLimit | null | undefined;
  const revoke = item.actions.find((a) => a.key === "revogar");
  const [target, setTarget] = useState<SocialAccount | null>(null);
  return (
    <>
      {accounts.length === 0 ? (
        <p className="text-muted-foreground">Este cliente ainda não tem contas {item.label} registadas. Acrescentam-se no calendário de publicações.</p>
      ) : (
        <ul className="flex flex-col divide-y rounded-md border">
          {accounts.map((a) => (
            <li key={a.account_id} className="flex flex-wrap items-center justify-between gap-2 p-2" data-social={a.account_id}>
              <div className="min-w-0">
                <span className="block truncate font-medium">@{a.handle}</span>
                <span className="block text-xs text-muted-foreground">
                  {["ligada", "a_expirar", "expirada"].includes(a.connection_state)
                    ? `${expiryText(a.token_expires_at)}${a.token_expires_at ? ` (${dateTime(a.token_expires_at, tz)})` : ""}`
                    : a.connection_state === "revogada" ? `revogada ${ago(a.updated_at)}` : "sem ligação"}
                </span>
                {a.scopes.length > 0 && <span className="block text-xs text-muted-foreground">Âmbitos concedidos: {a.scopes.join(", ")}</span>}
              </div>
              <div className="flex items-center gap-2">
                <StateBadge state={a.connection_state} />
                {a.can_revoke && revoke?.available && (
                  <Button size="sm" variant="outline" onClick={() => setTarget(a)} data-revoke={a.account_id}>Revogar</Button>
                )}
                {a.can_revoke && revoke && !revoke.available && <span className="text-xs text-muted-foreground">{revoke.reason}</span>}
              </div>
            </li>
          ))}
        </ul>
      )}
      {item.planned_permissions.length > 0 && (
        <div className="flex flex-col gap-1">
          <span className="text-xs text-muted-foreground">Permissões OAuth que a app vai pedir:</span>
          <div className="flex flex-wrap gap-1">{item.planned_permissions.map((p) => <Badge key={p} variant="outline">{p}</Badge>)}</div>
        </div>
      )}
      {lim && <LimitLine l={lim} />}
      {target && <RevokeDialog access={access} account={target} platform={item.label} onClose={() => setTarget(null)} onDone={() => { setTarget(null); onChanged(); }} />}
    </>
  );
}

function ScrapingDetail({ item, tz }: { item: IntegItem; tz: string }) {
  const accounts = (item.detail.accounts ?? []) as ScrapingAccount[];
  return (
    <>
      <p>
        Última sincronização: <span className="font-medium">{item.last_sync_at ? `${ago(item.last_sync_at)} (${dateTime(item.last_sync_at, tz)})` : "nunca"}</span>.
        {" "}Fica atrasada depois de {item.detail.stale_after_hours ?? 48} h sem novidades.
      </p>
      {accounts.length > 0 && (
        <ul className="flex flex-col gap-1 text-xs" aria-label="Por conta">
          {accounts.map((a) => (
            <li key={a.account_id} className="flex flex-wrap justify-between gap-2" data-scrape={a.account_id}>
              <span>@{a.handle} · {a.platform} · {a.reels} reels</span>
              <span className="text-muted-foreground">{stateLabel(a.state)} · {ago(a.last_sync_at)}</span>
            </li>
          ))}
        </ul>
      )}
      {item.detail.references_last_sync_at !== undefined && (
        <p className="text-xs text-muted-foreground">Referências: {ago(item.detail.references_last_sync_at)}.</p>
      )}
    </>
  );
}

function WorkerDetail({ item, tz }: { item: IntegItem; tz: string }) {
  const d = item.detail;
  const j = d.last_job;
  return (
    <>
      <p>Último contacto do worker: <span className="font-medium">{d.worker_seen_at ? `${ago(d.worker_seen_at)} (${dateTime(d.worker_seen_at, tz)})` : "nunca"}</span>.</p>
      {j ? (
        <p className="text-xs">
          Última execução: {j.kind} · {JOB_STATUS_LABEL[j.status] ?? j.status} · {ago(j.finished_at ?? j.started_at ?? j.created_at)}
          {j.last_error && <span className="block text-amber-500">Erro: {j.last_error}</span>}
        </p>
      ) : <p className="text-xs text-muted-foreground">Ainda não houve execuções neste cliente.</p>}
      <p className="text-xs text-muted-foreground">
        {d.queued ? `${d.queued} na fila${d.queue_late ? ", a mais antiga há mais de 1 h" : ""}.` : "Nada na fila."}
        {d.failed_7d ? ` ${d.failed_7d} falhadas nos últimos 7 dias.` : ""}
      </p>
    </>
  );
}

function TestRow({ item, action, access, tz, canManage, onChanged }: {
  item: IntegItem; action: IntegAction; access: Access; tz: string; canManage: boolean; onChanged: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [res, setRes] = useState<IntegCheck | null>(null);
  const last = res ?? item.last_check;
  const run = async () => {
    setBusy(true); setErr("");
    try { setRes(await testIntegration(access, item.key)); onChanged(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  return (
    <div className="mt-auto flex flex-col gap-1 border-t pt-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {last ? <>Último teste: <span className="font-medium text-foreground" data-outcome={last.outcome}>{OUTCOME_LABEL[last.outcome] ?? last.outcome}</span> · {dateTime(last.checked_at, tz)}{last.actor_label ? ` · ${last.actor_label}` : ""}</> : "Ainda não foi testada."}
        </span>
        {canManage && action.available && (
          <Button size="sm" variant="outline" onClick={() => void run()} disabled={busy} data-test-integration={item.key}>
            {busy ? <Loader2Icon className="animate-spin" /> : <RotateCwIcon />} Testar
          </Button>
        )}
      </div>
      {err && <p role="alert" className="text-xs text-destructive">{err}</p>}
    </div>
  );
}

function RevokeDialog({ access, account, platform, onClose, onDone }: {
  access: Access; account: SocialAccount; platform: string; onClose: () => void; onDone: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const submit = async () => {
    setBusy(true); setErr("");
    try { await revokeSocialAccount(access, account.account_id, reason.trim()); onDone(); }
    catch (e) { setErr((e as Error).message); setBusy(false); }
  };
  return (
    <Dialog open onOpenChange={(v) => { if (!v && !busy) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Revogar @{account.handle}</DialogTitle>
          <DialogDescription>
            A app deixa de usar a ligação {platform} desta conta e apaga a credencial guardada. Para voltar a usar, é preciso ligar de novo.
            Retira também o acesso nas definições da conta na plataforma.
          </DialogDescription>
        </DialogHeader>
        <label className="flex flex-col gap-1 text-sm">Motivo (fica no histórico)
          <Textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} rows={3} data-revoke-reason />
        </label>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Cancelar</Button>
          <Button variant="destructive" onClick={() => void submit()} disabled={busy || !reasonOk(reason)} data-revoke-confirm>
            {busy && <Loader2Icon className="animate-spin" />} Revogar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
