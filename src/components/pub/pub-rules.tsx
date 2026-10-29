"use client";

import { useState } from "react";
import { Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import type { Access } from "@/lib/access";
import { addAccount, saveLimit, savePolicy, type PlatformLimit, type PubCalendar } from "@/lib/pub";
import { CONNECTION_LABEL, PLATFORM_LABEL, PLATFORMS, POLICY_LABEL, PUBLISH_UNAVAILABLE, SCOPE_LABEL, WINDOW_LABEL, type Platform, type PolicyRequired } from "@/lib/pub-rules";

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm";
const fmtDate = (d: string) => new Intl.DateTimeFormat("pt-PT", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(d + "T12:00:00Z"));

/** Quem aprova (TEAM-10), limites das APIs (PUB-02) e contas de destino (FR-21-01). */
export function PubRulesSheet({ access, data, onClose, onChanged }: { access: Access; data: PubCalendar; onClose: () => void; onChanged: () => void }) {
  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>Regras e contas</SheetTitle>
          <SheetDescription>Quem aprova neste cliente, limites das APIs das plataformas e contas de destino.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-4 pb-6 text-sm">
          <PolicySection access={access} data={data} onChanged={onChanged} />
          <LimitsSection access={access} data={data} onChanged={onChanged} />
          <AccountsSection access={access} data={data} onChanged={onChanged} />
        </div>
      </SheetContent>
    </Sheet>
  );
}

function PolicySection({ access, data, onChanged }: { access: Access; data: PubCalendar; onChanged: () => void }) {
  const [required, setRequired] = useState<PolicyRequired>(data.policy.required);
  const [forbidSelf, setForbidSelf] = useState(data.policy.forbid_self);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad: boolean } | null>(null);
  const dirty = required !== data.policy.required || forbidSelf !== data.policy.forbid_self;
  const save = async () => {
    setBusy(true); setMsg(null);
    try {
      const r = await savePolicy(access, { required, forbid_self: forbidSelf });
      setMsg({ text: `Política guardada.${r.reopened ? ` ${r.reopened} publicação(ões) aprovada(s) voltaram a precisar de aprovação.` : ""}`, bad: false });
      onChanged();
    } catch (e) { setMsg({ text: (e as Error).message, bad: true }); }
    finally { setBusy(false); }
  };
  return (
    <section className="flex flex-col gap-2" aria-labelledby="pub-policy-title">
      <h3 id="pub-policy-title" className="font-semibold">Quem aprova</h3>
      <p className="text-muted-foreground">Aprovam publicações originais quem tem a capacidade &quot;Aprovar publicações&quot;; republicações precisam de &quot;Aprovar republicações&quot;. Dá-se por papel ou pessoa em Permissões.</p>
      <label className="flex flex-col gap-1">Aprovação exigida
        <select className={selectCls} value={required} disabled={!data.can.policy} onChange={(e) => setRequired(e.target.value as PolicyRequired)}>
          {(Object.keys(POLICY_LABEL) as PolicyRequired[]).map((k) => <option key={k} value={k}>{POLICY_LABEL[k]}</option>)}
        </select>
      </label>
      <label className="inline-flex items-center gap-2">
        <input type="checkbox" checked={forbidSelf} disabled={!data.can.policy} onChange={(e) => setForbidSelf(e.target.checked)} />
        Quem planeou ou mudou a publicação não a pode aprovar
      </label>
      {data.policy.updated_at && <p className="text-xs text-muted-foreground">Última mudança: {data.policy.updated_label ?? "?"}, {new Date(data.policy.updated_at).toLocaleString("pt-PT", { timeZone: data.timezone })}</p>}
      {data.can.policy ? (
        <Button className="self-start" size="sm" disabled={!dirty || busy} onClick={save}>{busy && <Loader2Icon className="animate-spin" />} Guardar política</Button>
      ) : <p className="text-xs text-muted-foreground">Só o dono ou admin do cliente muda a política.</p>}
      {msg && <p role={msg.bad ? "alert" : "status"} className={msg.bad ? "text-destructive" : ""}>{msg.text}</p>}
    </section>
  );
}

function LimitsSection({ access, data, onChanged }: { access: Access; data: PubCalendar; onChanged: () => void }) {
  const [limits, setLimits] = useState<PlatformLimit[]>(data.limits);
  const [edit, setEdit] = useState<Platform | null>(null);
  return (
    <section className="flex flex-col gap-2" aria-labelledby="pub-limits-title">
      <h3 id="pub-limits-title" className="font-semibold">Limites das APIs</h3>
      <p className="text-muted-foreground">O planeamento recusa o que passar o limite. {data.can.limits ? "" : "Só o dono da agência edita estes valores."}</p>
      <ul className="flex flex-col gap-2">
        {limits.map((l) => (
          <li key={l.platform} className="rounded-lg border p-3" data-limit={l.platform}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <b>{PLATFORM_LABEL[l.platform]}</b>
              <span className="text-xs text-muted-foreground">verificado a {fmtDate(l.verified_on)}</span>
            </div>
            <p>{l.max_posts} publicações {SCOPE_LABEL[l.scope]}, {WINDOW_LABEL[l.window_kind]}{l.window_kind === "calendar_day" ? ` (${l.window_tz})` : ""}{l.public_requires_audit ? " · só público depois da auditoria" : ""}.</p>
            {l.note && <p className="text-xs text-muted-foreground">{l.note}</p>}
            {(l.republish_min_days !== null || l.republish_max_share !== null) && (
              <p className="text-xs text-muted-foreground">Republicação [pressuposto VAR-05]: intervalo mínimo {l.republish_min_days ?? "?"} dias, até {l.republish_max_share !== null ? Math.round(l.republish_max_share * 100) : "?"}% em 30 dias, {l.republish_identical ? "idêntica com cautela" : "sem idênticas"}.</p>
            )}
            {data.can.limits && (edit === l.platform
              ? <LimitForm access={access} limit={l} onDone={(ls) => { if (ls) { setLimits(ls); onChanged(); } setEdit(null); }} />
              : <Button size="sm" variant="ghost" onClick={() => setEdit(l.platform)}>Editar {PLATFORM_LABEL[l.platform]}</Button>)}
          </li>
        ))}
      </ul>
    </section>
  );
}

function LimitForm({ access, limit, onDone }: { access: Access; limit: PlatformLimit; onDone: (l: PlatformLimit[] | null) => void }) {
  const [max, setMax] = useState(String(limit.max_posts));
  const [verified, setVerified] = useState("");
  const [note, setNote] = useState(limit.note ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const submit = async () => {
    setBusy(true); setErr("");
    try { onDone(await saveLimit(access, limit.platform, { max_posts: Number(max), verified_on: verified, note })); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  return (
    <form className="mt-2 flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); submit(); }}>
      <label className="flex flex-col gap-1">Máximo<Input type="number" min={1} max={10000} value={max} onChange={(e) => setMax(e.target.value)} /></label>
      <label className="flex flex-col gap-1">Verificado na documentação a<Input type="date" value={verified} onChange={(e) => setVerified(e.target.value)} required /></label>
      <label className="flex flex-col gap-1">Nota<Input value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} /></label>
      {err && <p role="alert" className="text-destructive">{err}</p>}
      <div className="flex gap-2">
        <Button type="button" size="sm" variant="ghost" onClick={() => onDone(null)}>Cancelar</Button>
        <Button type="submit" size="sm" disabled={busy || !verified || !(Number(max) >= 1)}>{busy && <Loader2Icon className="animate-spin" />} Guardar limite</Button>
      </div>
    </form>
  );
}

function AccountsSection({ access, data, onChanged }: { access: Access; data: PubCalendar; onChanged: () => void }) {
  const [platform, setPlatform] = useState<Platform>("tiktok");
  const [handle, setHandle] = useState("");
  const [label, setLabel] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad: boolean } | null>(null);
  const submit = async () => {
    setBusy(true); setMsg(null);
    try { const a = await addAccount(access, platform, handle.trim(), label.trim()); setMsg({ text: `@${a.handle} acrescentada (por ligar).`, bad: false }); setHandle(""); setLabel(""); onChanged(); }
    catch (e) { setMsg({ text: (e as Error).message, bad: true }); }
    finally { setBusy(false); }
  };
  return (
    <section className="flex flex-col gap-2" aria-labelledby="pub-accounts-title">
      <h3 id="pub-accounts-title" className="font-semibold">Contas de destino</h3>
      <p className="text-muted-foreground">Credenciais e permissões são por conta, nunca partilhadas. Ligar contas pela API oficial ainda não está disponível: {PUBLISH_UNAVAILABLE}</p>
      {data.accounts.length === 0 ? <p className="text-muted-foreground">Sem contas.</p> : (
        <ul className="flex flex-col divide-y rounded-lg border">
          {data.accounts.map((a) => (
            <li key={a.id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2" data-account={a.id}>
              <span>@{a.handle} · {PLATFORM_LABEL[a.platform] ?? a.platform}{a.active ? "" : " · inativa"}</span>
              <span className="text-xs text-muted-foreground">{CONNECTION_LABEL[a.connection_state] ?? a.connection_state}</span>
            </li>
          ))}
        </ul>
      )}
      {data.can.accounts && (
        <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); submit(); }}>
          <div className="grid gap-2 sm:grid-cols-3">
            <select aria-label="Plataforma da conta" className={selectCls} value={platform} onChange={(e) => setPlatform(e.target.value as Platform)}>
              {PLATFORMS.map((p) => <option key={p} value={p}>{PLATFORM_LABEL[p]}</option>)}
            </select>
            <Input aria-label="Nome da conta" placeholder="nome da conta, sem @" value={handle} onChange={(e) => setHandle(e.target.value)} />
            <Input aria-label="Descrição da conta" placeholder="Descrição (opcional)" value={label} maxLength={80} onChange={(e) => setLabel(e.target.value)} />
          </div>
          <Button className="self-start" size="sm" type="submit" disabled={busy || !handle.trim()}>{busy && <Loader2Icon className="animate-spin" />} Acrescentar conta</Button>
        </form>
      )}
      {msg && <p role={msg.bad ? "alert" : "status"} className={msg.bad ? "text-destructive" : ""}>{msg.text}</p>}
    </section>
  );
}
