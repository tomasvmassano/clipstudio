"use client";

import Link from "next/link";
import { Suspense, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { ArrowLeftIcon, HistoryIcon, PencilIcon, PlusIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { FlagGate } from "@/components/flag-gate";
import { useSession } from "@/components/session-provider";
import {
  ALLOCATION_LABEL, KIND_LABEL, PAYMENT_LABEL, PERIOD_LABEL, currentMonth, fetchContractHistory, fetchContracts, fetchCosts, fmtDate, fmtMoney, fmtNum,
  isForbidden, monthLabel, saveContract, saveCost, saveFx, voidCost,
  type Allocation, type BillingPeriod, type Contract, type ContractsResp, type CostKind, type CostsResp, type Currency, type PaymentStatus,
} from "@/lib/biz";

/** Contratos por cliente (BIZ-05), câmbio e custos (BIZ-06). Registo interno, não faturação. Só o dono da agência por defeito. */
export default function ContratosPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("biz.finance")) return <Alert><AlertDescription>Contratos, câmbio e custos são só para o dono da agência.</AlertDescription></Alert>;
  return (
    <FlagGate flag="biz.view" ws={null}>
      <Suspense fallback={<Skeleton className="h-64" />}><Contratos /></Suspense>
    </FlagGate>
  );
}

const sel = "h-8 w-full rounded-md border bg-background px-2 text-sm";

function Contratos() {
  const focus = useSearchParams().get("ws");
  const [data, setData] = useState<ContractsResp | null>(null);
  const [err, setErr] = useState<{ msg: string; forbidden: boolean } | null>(null);
  const load = useCallback(() => {
    setErr(null);
    fetchContracts().then(setData).catch((e: Error) => setErr({ msg: e.message, forbidden: isForbidden(e) }));
  }, []);
  useEffect(() => {
    let alive = true;
    fetchContracts().then((d) => { if (alive) setData(d); }).catch((e: Error) => { if (alive) setErr({ msg: e.message, forbidden: isForbidden(e) }); });
    return () => { alive = false; };
  }, []);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href="/negocio" className="inline-flex items-center gap-1 text-muted-foreground text-xs hover:text-foreground"><ArrowLeftIcon className="size-3" /> Vista de negócio</Link>
        <h1 className="text-2xl font-semibold tracking-tight">Contratos e custos</h1>
        <p className="text-sm text-muted-foreground">Registo interno do que cada cliente contratou, do câmbio e dos custos. Não é faturação. Cada gravação fica como versão nova no histórico.</p>
      </div>
      {err && (err.forbidden ? <Alert><AlertDescription>{err.msg}</AlertDescription></Alert> : (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">Não consegui carregar os contratos: {err.msg}
          <Button size="sm" variant="outline" onClick={load}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ))}
      {!data && !err && <Skeleton className="h-64" />}
      {data && (
        <>
          <FxSection data={data} onSaved={setData} />
          <section aria-labelledby="contracts" className="flex flex-col gap-2">
            <h2 id="contracts" className="font-medium text-base">Contratos por cliente</h2>
            {data.clients.length === 0 ? <p className="text-muted-foreground text-sm">Ainda não há clientes ativos.</p> : (
              <ul className="flex flex-col gap-3">
                {data.clients.map((c) => <ContractCard key={c.id} c={c} canManage={data.can_manage} initiallyOpen={focus === c.id} onSaved={setData} />)}
              </ul>
            )}
          </section>
          <CostsSection clients={data.clients.map((c) => ({ id: c.id, name: c.name }))} />
        </>
      )}
    </div>
  );
}

function FxSection({ data, onSaved }: { data: ContractsResp; onSaved: (d: ContractsResp) => void }) {
  const [rate, setRate] = useState("");
  const [asOf, setAsOf] = useState(() => new Date().toISOString().slice(0, 10));
  const [source, setSource] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const r = Number(rate.replace(",", "."));
    if (!(r > 0)) { setMsg({ ok: false, text: "Indica uma taxa maior que 0 (AED por 1 EUR)." }); return; }
    setBusy(true); setMsg(null);
    try { onSaved(await saveFx(r, asOf, source)); setRate(""); setSource(""); setMsg({ ok: true, text: "Taxa gravada." }); }
    catch (er) { setMsg({ ok: false, text: (er as Error).message }); }
    finally { setBusy(false); }
  };
  return (
    <section aria-labelledby="fx" className="flex flex-col gap-2">
      <h2 id="fx" className="font-medium text-base">Câmbio EUR/AED</h2>
      <p className="text-sm">
        {data.fx ? <>Atual: <strong>1 EUR = {fmtNum(data.fx.rate, 4)} AED</strong>, taxa de {fmtDate(data.fx.as_of)}{data.fx.source ? ` (${data.fx.source})` : ""}.</>
          : <span className="text-amber-500">Ainda não há taxa: os totais não convertem valores noutra moeda.</span>}
      </p>
      {data.can_manage && (
        <form onSubmit={submit} className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs">AED por 1 EUR<Input inputMode="decimal" value={rate} onChange={(e) => setRate(e.target.value)} className="w-32" required /></label>
          <label className="flex flex-col gap-1 text-xs">Data da taxa<Input type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} className="w-40" required /></label>
          <label className="flex flex-col gap-1 text-xs">Fonte (opcional)<Input value={source} maxLength={120} onChange={(e) => setSource(e.target.value)} className="w-48" /></label>
          <Button type="submit" size="sm" disabled={busy}>{busy ? "A gravar..." : "Gravar taxa"}</Button>
        </form>
      )}
      {msg && <p role="status" className={`text-xs ${msg.ok ? "text-emerald-500" : "text-red-500"}`}>{msg.text}</p>}
      {data.fx_history.length > 1 && (
        <details className="text-xs text-muted-foreground"><summary className="cursor-pointer">Taxas anteriores</summary>
          <ul className="mt-1 flex flex-col gap-0.5">{data.fx_history.map((h, i) => <li key={i}>{fmtDate(h.as_of)}: {fmtNum(h.rate, 4)}{h.source ? ` (${h.source})` : ""}{h.created_label ? ` · ${h.created_label}` : ""}</li>)}</ul>
        </details>
      )}
    </section>
  );
}

type Form = {
  status: "ativo" | "terminado"; amount: string; currency: Currency; billing_period: BillingPeriod; videos_per_month: string; scripts_per_month: string;
  platforms: string[]; deadline_days: string; starts_on: string; renewal_on: string; effective_from: string; payment_status: PaymentStatus; payment_due_on: string; notes: string;
};
const today = () => new Date().toISOString().slice(0, 10);
function toForm(k: Contract | null): Form {
  return {
    status: k?.status ?? "ativo", amount: k ? String(k.amount) : "", currency: k?.currency ?? "EUR", billing_period: k?.billing_period ?? "mensal",
    videos_per_month: k?.videos_per_month?.toString() ?? "", scripts_per_month: k?.scripts_per_month?.toString() ?? "", platforms: k?.platforms ?? [],
    deadline_days: String(k?.deadline_days ?? 7), starts_on: k?.starts_on ?? "", renewal_on: k?.renewal_on ?? "", effective_from: today(),
    payment_status: k?.payment_status ?? "em_dia", payment_due_on: k?.payment_due_on ?? "", notes: k?.notes ?? "",
  };
}
const PLATFORMS = [{ k: "instagram", l: "Instagram" }, { k: "tiktok", l: "TikTok" }, { k: "youtube", l: "YouTube" }];

function ContractCard({ c, canManage, initiallyOpen, onSaved }: { c: ContractsResp["clients"][number]; canManage: boolean; initiallyOpen: boolean; onSaved: (d: ContractsResp) => void }) {
  const k = c.contract;
  const [editing, setEditing] = useState(initiallyOpen && canManage);
  const [form, setForm] = useState<Form>(() => toForm(k));
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [history, setHistory] = useState<Contract[] | null>(null);
  const [histErr, setHistErr] = useState("");
  const set = <K extends keyof Form>(key: K, v: Form[K]) => setForm((f) => ({ ...f, [key]: v }));
  const id = `c-${c.id}`;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setMsg(null);
    const n = (s: string) => (s.trim() === "" ? null : Number(s.replace(",", ".")));
    try {
      const d = await saveContract(c.id, {
        status: form.status, amount: n(form.amount), currency: form.currency, billing_period: form.billing_period,
        videos_per_month: n(form.videos_per_month), scripts_per_month: n(form.scripts_per_month), platforms: form.platforms,
        deadline_days: n(form.deadline_days), starts_on: form.starts_on, renewal_on: form.renewal_on, effective_from: form.effective_from,
        payment_status: form.payment_status, payment_due_on: form.payment_due_on, notes: form.notes,
      }, k?.version ?? 0);
      onSaved(d);
      setEditing(false); setHistory(null);
      setMsg({ ok: true, text: "Contrato gravado como versão nova." });
    } catch (er) { setMsg({ ok: false, text: (er as Error).message }); }
    finally { setBusy(false); }
  };
  const showHistory = async () => {
    if (history) { setHistory(null); return; }
    setHistErr("");
    try { setHistory(await fetchContractHistory(c.id)); } catch (er) { setHistErr((er as Error).message); }
  };

  return (
    <li id={id} data-contract={c.id}>
      <Card className={`shadow-none dark:ring-0 ${initiallyOpen ? "ring-1 ring-primary" : ""}`}>
        <CardContent className="flex flex-col gap-3 py-3">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="font-medium">{c.name}</p>
              {k ? (
                <p className="text-muted-foreground text-xs">
                  {fmtMoney(k.amount, k.currency)} {PERIOD_LABEL[k.billing_period].toLowerCase()} · {k.videos_per_month ?? "-"} vídeos/mês · {k.scripts_per_month ?? "-"} guiões/mês
                  {k.platforms.length ? ` · ${k.platforms.join(", ")}` : ""} · prazo {k.deadline_days} dias · pagamento {PAYMENT_LABEL[k.payment_status].toLowerCase()}
                  {k.payment_due_on ? ` (vence ${fmtDate(k.payment_due_on)})` : ""} · renovação {fmtDate(k.renewal_on)}{k.status === "terminado" ? " · terminado" : ""} · versão {k.version}
                </p>
              ) : <p className="text-muted-foreground text-xs">Sem contrato registado: o atingimento e a margem deste cliente ficam indisponíveis.</p>}
            </div>
            <div className="flex gap-2">
              {c.versions > 0 && <Button size="sm" variant="ghost" onClick={showHistory} aria-expanded={!!history}><HistoryIcon /> Histórico</Button>}
              {canManage && !editing && <Button size="sm" variant="outline" onClick={() => { setForm(toForm(k)); setEditing(true); setMsg(null); }}>
                {k ? <><PencilIcon /> Mudar</> : <><PlusIcon /> Registar contrato</>}</Button>}
            </div>
          </div>
          {msg && <p role="status" className={`text-xs ${msg.ok ? "text-emerald-500" : "text-red-500"}`}>{msg.text}</p>}
          {histErr && <p className="text-red-500 text-xs">{histErr}</p>}
          {history && (
            <ol className="flex flex-col gap-1 border-t pt-2 text-xs" aria-label={`Versões do contrato de ${c.name}`}>
              {history.map((h) => (
                <li key={h.id} className="text-muted-foreground">
                  <span className="font-medium text-foreground">v{h.version}</span> · em vigor desde {fmtDate(h.effective_from)} · {fmtMoney(h.amount, h.currency)} {PERIOD_LABEL[h.billing_period].toLowerCase()}
                  {" "}· {h.videos_per_month ?? "-"} vídeos · {PAYMENT_LABEL[h.payment_status]} · {h.status} · gravado {new Date(h.created_at).toLocaleString("pt-PT")}{h.created_label ? ` por ${h.created_label}` : ""}
                </li>
              ))}
            </ol>
          )}
          {editing && (
            <form onSubmit={submit} className="grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-2 lg:grid-cols-4" aria-label={`Contrato de ${c.name}`}>
              <label className="flex flex-col gap-1 text-xs">Valor<Input inputMode="decimal" required value={form.amount} onChange={(e) => set("amount", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Moeda
                <select className={sel} value={form.currency} onChange={(e) => set("currency", e.target.value as Currency)}><option value="EUR">EUR</option><option value="AED">AED</option></select>
              </label>
              <label className="flex flex-col gap-1 text-xs">Periodicidade
                <select className={sel} value={form.billing_period} onChange={(e) => set("billing_period", e.target.value as BillingPeriod)}>
                  {(Object.keys(PERIOD_LABEL) as BillingPeriod[]).map((p) => <option key={p} value={p}>{PERIOD_LABEL[p]}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-xs">Estado
                <select className={sel} value={form.status} onChange={(e) => set("status", e.target.value as Form["status"])}><option value="ativo">Ativo</option><option value="terminado">Terminado</option></select>
              </label>
              <label className="flex flex-col gap-1 text-xs">Vídeos por mês<Input inputMode="numeric" value={form.videos_per_month} onChange={(e) => set("videos_per_month", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Guiões por mês<Input inputMode="numeric" value={form.scripts_per_month} onChange={(e) => set("scripts_per_month", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Prazo de publicação (dias depois do guião)<Input inputMode="numeric" value={form.deadline_days} onChange={(e) => set("deadline_days", e.target.value)} /></label>
              <fieldset className="flex flex-col gap-1 text-xs"><legend className="mb-1">Plataformas</legend>
                <div className="flex flex-wrap gap-3">{PLATFORMS.map((p) => (
                  <label key={p.k} className="flex items-center gap-1"><input type="checkbox" checked={form.platforms.includes(p.k)}
                    onChange={(e) => set("platforms", e.target.checked ? [...form.platforms, p.k] : form.platforms.filter((x) => x !== p.k))} />{p.l}</label>
                ))}</div>
              </fieldset>
              <label className="flex flex-col gap-1 text-xs">Início<Input type="date" value={form.starts_on} onChange={(e) => set("starts_on", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Renovação<Input type="date" value={form.renewal_on} onChange={(e) => set("renewal_on", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Pagamento
                <select className={sel} value={form.payment_status} onChange={(e) => set("payment_status", e.target.value as PaymentStatus)}>
                  {(Object.keys(PAYMENT_LABEL) as PaymentStatus[]).map((p) => <option key={p} value={p}>{PAYMENT_LABEL[p]}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-xs">Vencimento<Input type="date" value={form.payment_due_on} onChange={(e) => set("payment_due_on", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs">Em vigor desde<Input type="date" required value={form.effective_from} onChange={(e) => set("effective_from", e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs sm:col-span-2 lg:col-span-3">Notas<Textarea maxLength={1000} rows={2} value={form.notes} onChange={(e) => set("notes", e.target.value)} /></label>
              <div className="flex items-end gap-2 sm:col-span-2 lg:col-span-4">
                <Button type="submit" size="sm" disabled={busy}>{busy ? "A gravar..." : "Gravar versão nova"}</Button>
                <Button type="button" size="sm" variant="ghost" onClick={() => setEditing(false)} disabled={busy}>Cancelar</Button>
              </div>
            </form>
          )}
        </CardContent>
      </Card>
    </li>
  );
}

function CostsSection({ clients }: { clients: { id: string; name: string }[] }) {
  const [month, setMonth] = useState(currentMonth);
  const [data, setData] = useState<CostsResp | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [form, setForm] = useState({ workspace_id: "", kind: "humano" as CostKind, label: "", amount: "", currency: "EUR" as Currency, allocation: "igual" as Allocation });
  const [ref, setRef] = useState(() => crypto.randomUUID());
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [voiding, setVoiding] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  useEffect(() => {
    let alive = true;
    fetchCosts(`${month}-01`).then((d) => { if (alive) { setData(d); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [month, rev]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setMsg(null);
    try {
      const d = await saveCost({
        workspace_id: form.workspace_id || null, month: `${month}-01`, kind: form.kind, label: form.label, amount: Number(form.amount.replace(",", ".")),
        currency: form.currency, allocation: form.workspace_id ? "direto" : form.allocation,
      }, ref);
      setData(d); setRef(crypto.randomUUID()); setForm((f) => ({ ...f, label: "", amount: "" }));
      setMsg({ ok: true, text: "Custo acrescentado." });
    } catch (er) { setMsg({ ok: false, text: (er as Error).message }); }   // a mesma referência: repetir não duplica
    finally { setBusy(false); }
  };
  const doVoid = async (id: string) => {
    if (!reason.trim()) { setMsg({ ok: false, text: "Escreve o motivo para anular." }); return; }
    setBusy(true); setMsg(null);
    try { setData(await voidCost(id, reason)); setVoiding(null); setReason(""); setMsg({ ok: true, text: "Custo anulado. Fica no histórico." }); }
    catch (er) { setMsg({ ok: false, text: (er as Error).message }); }
    finally { setBusy(false); }
  };

  return (
    <section aria-labelledby="costs" className="flex flex-col gap-2">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <h2 id="costs" className="font-medium text-base">Custos de {monthLabel(month)}</h2>
        <label className="flex flex-col gap-1 text-xs">Mês<Input type="month" value={month} max={currentMonth()} onChange={(e) => { if (e.target.value) setMonth(e.target.value); }} className="w-40" /></label>
      </div>
      <p className="text-muted-foreground text-xs">O custo de IA vem das execuções dos agentes. Aqui entram custos humanos, ferramentas e outros: diretos a um cliente, ou da agência repartidos por todos os clientes ativos (por igual ou pelos vídeos publicados no mês).</p>
      {err && <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">Não consegui carregar os custos: {err}
        <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>}
      {!data && !err && <Skeleton className="h-32" />}
      {data && (
        <>
          {data.costs.length === 0 ? <p className="rounded-lg border border-dashed p-4 text-muted-foreground text-sm">Sem custos registados neste mês.</p> : (
            <div className="overflow-x-auto rounded-lg border">
              <table className="w-full min-w-[640px] text-sm">
                <thead><tr className="border-b text-left text-xs text-muted-foreground">
                  <th scope="col" className="px-3 py-2 font-normal">Descrição</th><th scope="col" className="px-3 py-2 font-normal">Tipo</th>
                  <th scope="col" className="px-3 py-2 font-normal">Cliente / repartição</th><th scope="col" className="px-3 py-2 text-right font-normal">Valor</th>
                  <th scope="col" className="px-3 py-2"><span className="sr-only">Ações</span></th>
                </tr></thead>
                <tbody>
                  {data.costs.map((k) => (
                    <tr key={k.id} className={`border-b last:border-0 ${k.voided_at ? "text-muted-foreground line-through" : ""}`} data-cost={k.id}>
                      <td className="px-3 py-2">{k.label}{k.voided_at && <span className="block text-xs no-underline">anulado: {k.void_reason}</span>}</td>
                      <td className="px-3 py-2">{KIND_LABEL[k.kind]}</td>
                      <td className="px-3 py-2">{k.client_name ?? ALLOCATION_LABEL[k.allocation]}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmtMoney(k.amount, k.currency)}</td>
                      <td className="px-3 py-2 text-right">
                        {data.can_manage && !k.voided_at && (voiding === k.id ? (
                          <span className="inline-flex items-center gap-1">
                            <Input aria-label="Motivo para anular" placeholder="Motivo" value={reason} onChange={(e) => setReason(e.target.value)} className="h-7 w-36" />
                            <Button size="sm" variant="destructive" disabled={busy} onClick={() => void doVoid(k.id)}>Anular</Button>
                            <Button size="sm" variant="ghost" onClick={() => setVoiding(null)}>Cancelar</Button>
                          </span>
                        ) : <Button size="sm" variant="ghost" onClick={() => { setVoiding(k.id); setReason(""); }}>Anular</Button>)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {data.can_manage && (
            <form onSubmit={submit} className="grid grid-cols-1 gap-3 rounded-lg border p-3 sm:grid-cols-3 lg:grid-cols-6" aria-label="Acrescentar custo">
              <label className="flex flex-col gap-1 text-xs lg:col-span-2">Descrição<Input required minLength={2} maxLength={120} value={form.label} onChange={(e) => setForm({ ...form, label: e.target.value })} /></label>
              <label className="flex flex-col gap-1 text-xs">Tipo
                <select className={sel} value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value as CostKind })}>
                  {(Object.keys(KIND_LABEL) as CostKind[]).map((x) => <option key={x} value={x}>{KIND_LABEL[x]}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-xs">Cliente
                <select className={sel} value={form.workspace_id} onChange={(e) => setForm({ ...form, workspace_id: e.target.value })}>
                  <option value="">Agência (repartido)</option>
                  {clients.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </label>
              {!form.workspace_id && (
                <label className="flex flex-col gap-1 text-xs">Repartição
                  <select className={sel} value={form.allocation} onChange={(e) => setForm({ ...form, allocation: e.target.value as Allocation })}>
                    <option value="igual">{ALLOCATION_LABEL.igual}</option><option value="por_videos">{ALLOCATION_LABEL.por_videos}</option>
                  </select>
                </label>
              )}
              <label className="flex flex-col gap-1 text-xs">Valor<Input required inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></label>
              <label className="flex flex-col gap-1 text-xs">Moeda
                <select className={sel} value={form.currency} onChange={(e) => setForm({ ...form, currency: e.target.value as Currency })}><option value="EUR">EUR</option><option value="AED">AED</option></select>
              </label>
              <div className="flex items-end"><Button type="submit" size="sm" disabled={busy}>{busy ? "A gravar..." : "Acrescentar custo"}</Button></div>
            </form>
          )}
        </>
      )}
      {msg && <p role="status" className={`text-xs ${msg.ok ? "text-emerald-500" : "text-red-500"}`}>{msg.text}</p>}
    </section>
  );
}
