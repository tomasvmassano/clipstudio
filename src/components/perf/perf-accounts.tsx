"use client";

import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import type { Access } from "@/lib/access";
import { setAccount, type PerfAccount, type PerfCenter } from "@/lib/perf";
import { AGE_LABEL, AGES, HEALTH_LABEL, INSUFFICIENT, TIER_LABEL, UNAVAILABLE, dateTime, fmtPct, fmtPerK } from "@/lib/perf-format";
import { Field, Idx, selectClass } from "@/components/perf/perf-shared";

/* PERF-01 hierarquia (cliente → criador → conta), PERF-05 saúde e ressonância por conta, PERF-03 cobertura das fotografias. */

function AccountEditor({ access, acc, onSaved, onCancel }: { access: Access; acc: PerfAccount; onSaved: (c: PerfCenter) => void; onCancel: () => void }) {
  const [tier, setTier] = useState(acc.tier ?? "");
  const [creator, setCreator] = useState(acc.creator);
  const [state, setState] = useState(acc.health.state);
  const [note, setNote] = useState(acc.health.note ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const p = `acc-${acc.id}`;
  return (
    <form className="mt-3 grid gap-3 rounded-md border p-3 sm:grid-cols-2" onSubmit={async (e) => {
      e.preventDefault(); setBusy(true); setErr("");
      try { onSaved(await setAccount(access, acc.id, { tier: tier || null, creator: creator.trim() || null, health_state: state, health_note: note.trim() || null })); }
      catch (x) { setErr((x as Error).message); }
      finally { setBusy(false); }
    }}>
      <Field id={`${p}-tier`} label="Camada">
        <select id={`${p}-tier`} className={selectClass} value={tier} onChange={(e) => setTier(e.target.value)}>
          <option value="">Sem camada</option>
          {Object.entries(TIER_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </Field>
      <Field id={`${p}-creator`} label="Criador ou marca">
        <Input id={`${p}-creator`} value={creator} maxLength={80} onChange={(e) => setCreator(e.target.value)} />
      </Field>
      <Field id={`${p}-state`} label="Estado da conta (registado à mão)">
        <select id={`${p}-state`} className={selectClass} value={state} onChange={(e) => setState(e.target.value)}>
          {Object.entries(HEALTH_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </Field>
      <Field id={`${p}-note`} label="Nota do estado">
        <Input id={`${p}-note`} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} placeholder="Ex.: aviso de alcance reduzido na app" />
      </Field>
      {err && <p role="alert" className="text-sm text-destructive sm:col-span-2">{err}</p>}
      <div className="flex gap-2 sm:col-span-2">
        <Button type="submit" size="sm" disabled={busy}>{busy ? "A gravar…" : "Gravar conta"}</Button>
        <Button type="button" size="sm" variant="ghost" onClick={onCancel} disabled={busy}>Cancelar</Button>
      </div>
    </form>
  );
}

function Health({ acc, minBase }: { acc: PerfAccount; minBase: number }) {
  const h = acc.health;
  return (
    <dl className="grid grid-cols-1 gap-x-4 gap-y-1 text-sm sm:grid-cols-2">
      <dt className="text-muted-foreground">Mediana às 72 h (7 dias vs 30 anteriores)</dt>
      <dd>{h.median_ratio == null
        ? <span className="text-muted-foreground">{INSUFFICIENT} ({h.recent_n} recentes, {h.prev_n} de {minBase} na base)</span>
        : <span className={h.median_drop ? "font-medium text-amber-700 dark:text-amber-400" : ""}>{fmtPct(h.median_ratio)}{h.median_drop ? " · a cair" : ""}</span>}</dd>
      <dt className="text-muted-foreground">Posts perto de zero (30 dias)</dt>
      <dd>{h.near_zero_30d == null ? <span className="text-muted-foreground">{INSUFFICIENT}</span>
        : <>{fmtPct(h.near_zero_30d)}{h.near_zero_doubling ? <span className="font-medium text-amber-700 dark:text-amber-400"> · a duplicar</span> : null}</>}</dd>
      <dt className="text-muted-foreground">% For You a cair</dt>
      <dd className="text-muted-foreground">{UNAVAILABLE}</dd>
      <dt className="text-muted-foreground">Estado registado</dt>
      <dd>{HEALTH_LABEL[h.state] ?? h.state}{h.note ? ` · ${h.note}` : ""}{h.set_label ? <span className="text-muted-foreground"> ({h.set_label})</span> : null}</dd>
    </dl>
  );
}

export function PerfAccounts({ access, center, onChange }: { access: Access; center: PerfCenter; onChange: (c: PerfCenter) => void }) {
  const [editing, setEditing] = useState<string | null>(null);
  const tz = center.client.timezone;
  const creators = Array.from(new Set(center.accounts.map((a) => a.creator)));
  return (
    <div className="flex flex-col gap-4">
      <Card className="shadow-none dark:ring-0">
        <CardHeader>
          <CardTitle>Fotografias por idade</CardTitle>
          <CardDescription>
            Publicações com leitura perto de cada idade (±{Math.round(center.params.tolerance * 100)}%) e com índice (base de pelo menos {center.params.min_base} publicações da mesma conta nos 30 dias anteriores).
            {center.first_reading_at ? ` Leituras guardadas desde ${dateTime(center.first_reading_at, tz)}.` : " Ainda não há leituras guardadas: a recolha corre de hora a hora."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5" aria-label="Cobertura por idade">
            {AGES.map((a) => (
              <li key={a} className="rounded-md border p-2 text-sm">
                <div className="font-medium">{AGE_LABEL[a]}</div>
                <div className="text-muted-foreground">{center.coverage[a]?.snapshots ?? 0} fotografias</div>
                <div className="text-muted-foreground">{center.coverage[a]?.indexed ?? 0} com índice</div>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-sm text-muted-foreground">
            {center.totals.publications} publicações: {center.totals.sistema} com origem sistema, {center.totals.externo} externas; {center.totals.gravada} com linhagem gravada, {center.totals.inferida} inferidas ({center.totals.linked} ligadas a um guião).
          </p>
        </CardContent>
      </Card>

      <section aria-label={`Cliente ${center.client.name}`} className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{center.client.name}</h2>
        {center.accounts.length === 0 && <p className="text-sm text-muted-foreground">Este cliente ainda não tem contas próprias registadas.</p>}
        {creators.map((cr) => (
          <div key={cr} className="flex flex-col gap-3">
            <h3 className="text-sm font-medium text-muted-foreground">Criador ou marca: {cr}</h3>
            {center.accounts.filter((a) => a.creator === cr).map((a) => (
              <Card key={a.id} className="shadow-none dark:ring-0" data-account={a.id}>
                <CardHeader>
                  <div className="flex flex-wrap items-center gap-2">
                    <CardTitle className="break-all">@{a.handle} · {a.platform}</CardTitle>
                    <Badge variant="outline">{a.tier ? `Camada ${TIER_LABEL[a.tier] ?? a.tier}` : "Sem camada"}</Badge>
                    {!a.active && <Badge variant="secondary">Inativa</Badge>}
                  </div>
                  <CardDescription>
                    {a.n} publicações, {a.n_30d} nos últimos 30 dias{a.last_read_at ? `; última leitura ${dateTime(a.last_read_at, tz)}` : ""}.
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                  <dl className="grid grid-cols-1 gap-x-4 gap-y-1 text-sm sm:grid-cols-2">
                    <dt className="text-muted-foreground">Índice mediano às 72 h (30 dias)</dt>
                    <dd><Idx value={a.idx72_median_30d} reason={a.idx72_n_30d ? undefined : `${INSUFFICIENT} (nenhuma publicação com índice)`} />
                      {a.idx72_n_30d ? <span className="text-muted-foreground"> em {a.idx72_n_30d}</span> : null}</dd>
                    <dt className="text-muted-foreground">Comentários por 1.000 views</dt>
                    <dd>{a.comments_pk == null ? <span className="text-muted-foreground">Sem dados</span> : fmtPerK(a.comments_pk)}</dd>
                    <dt className="text-muted-foreground">Gostos por 1.000 views</dt>
                    <dd>{a.likes_pk == null ? <span className="text-muted-foreground">Sem dados</span> : fmtPerK(a.likes_pk)}</dd>
                    <dt className="text-muted-foreground">Partilhas por 1.000 views</dt>
                    <dd>{a.shares_available && a.shares_pk != null ? fmtPerK(a.shares_pk) : <span className="text-muted-foreground">A recolha desta conta não devolve partilhas</span>}</dd>
                  </dl>
                  <Health acc={a} minBase={center.params.min_base} />
                  {center.can_manage && editing !== a.id && (
                    <div><Button size="sm" variant="outline" onClick={() => setEditing(a.id)}>Mudar camada e estado</Button></div>
                  )}
                  {editing === a.id && (
                    <AccountEditor access={access} acc={a} onCancel={() => setEditing(null)} onSaved={(c) => { setEditing(null); onChange(c); }} />
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
        ))}
      </section>
    </div>
  );
}

export function PerfFamilies({ center }: { center: PerfCenter }) {
  return (
    <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
      {center.families.map((f) => (
        <Card key={f.key} className="shadow-none dark:ring-0">
          <CardHeader><CardTitle>{f.label}</CardTitle></CardHeader>
          <CardContent>
            <ul className="flex flex-col gap-2 text-sm">
              {f.metrics.map((m) => (
                <li key={m.key} className="flex flex-col">
                  <span className="flex flex-wrap items-center gap-2">
                    {m.label}
                    <Badge variant={m.available ? "secondary" : "outline"}>{m.available === "conta" ? "Depende da conta" : m.available ? "Disponível" : "Indisponível"}</Badge>
                  </span>
                  {!m.available && <span className="text-xs text-muted-foreground">{m.reason ?? UNAVAILABLE}</span>}
                  {m.note && <span className="text-xs text-muted-foreground">{m.note}</span>}
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
