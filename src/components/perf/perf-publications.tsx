"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { Access } from "@/lib/access";
import { fetchPublications, setOrigin, type PerfCenter, type PerfFilters, type Publication } from "@/lib/perf";
import {
  AGE_LABEL, AGES, INFERENCE_LABEL, MECHANISM_LABEL, TIER_LABEL, UNAVAILABLE, dateTime, fmtPerK, idxMissingReason,
} from "@/lib/perf-format";
import { Field, Idx, LoadState, OriginBadge, selectClass, useLoad } from "@/components/perf/perf-shared";

/* PERF-02 (etiquetas), PERF-03 (fotografias por idade), PERF-04 (índice), R-16 (origem e correção), R-18 (linhagem). */

const PAGE = 50;
const SOURCE_LABEL: Record<string, string> = { guiao: "Guião", fonte_longa: "Fonte longa", telemovel: "Telemóvel", lifestyle: "Lifestyle" };
const ORIGIN_SOURCE: Record<string, string> = { publicador: "publicador", correspondencia: "correspondência com um render nosso", importacao: "importação", manual: "corrigida à mão" };

function Tag({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="break-words">{value === null || value === undefined || value === "" ? <span className="text-muted-foreground">Sem registo</span> : value}</dd>
    </>
  );
}

function OriginForm({ access, pub, onDone }: { access: Access; pub: Publication; onDone: () => void }) {
  const target = pub.origin === "sistema" ? "externo" : "sistema";
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");
  return (
    <form className="flex flex-col gap-2 rounded-md border p-3" onSubmit={async (e) => {
      e.preventDefault(); setBusy(true); setErr(""); setOk("");
      try { await setOrigin(access, pub.account_id, pub.reel_id, target, reason); setOk(`Origem mudada para ${target}.`); onDone(); }
      catch (x) { setErr((x as Error).message); }
      finally { setBusy(false); }
    }}>
      <Field id="origin-reason" label={`Mudar a origem para ${target === "sistema" ? "Sistema" : "Externo"} (fica no histórico)`}>
        <Input id="origin-reason" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} placeholder="Motivo, ex.: render nosso publicado à mão" />
      </Field>
      {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
      {ok && <p role="status" className="text-sm">{ok}</p>}
      <div><Button type="submit" size="sm" disabled={busy || reason.trim().length < 3}>{busy ? "A gravar…" : "Mudar origem"}</Button></div>
    </form>
  );
}

function Details({ access, pub, center, onClose, onChanged }: { access: Access; pub: Publication; center: PerfCenter; onClose: () => void; onChanged: () => void }) {
  const tz = center.client.timezone;
  return (
    <Sheet open onOpenChange={(o) => { if (!o) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle className="break-words">{pub.title}</SheetTitle>
          <SheetDescription>@{pub.handle} · {pub.platform} · {dateTime(pub.published_at, tz) || "sem data"}</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6 text-sm">
          <div className="flex flex-col gap-1">
            <OriginBadge origin={pub.origin} mode={pub.lineage_mode} />
            <p className="text-muted-foreground">
              Origem por {ORIGIN_SOURCE[pub.origin_source] ?? pub.origin_source}.
              {pub.lineage_mode === "inferida"
                ? ` Etiquetas inferidas depois da publicação (${INFERENCE_LABEL[pub.inference_source ?? "nenhuma"] ?? pub.inference_source}${pub.inference_confidence != null ? `, confiança ${Math.round(pub.inference_confidence * 100)}%` : ""}); a linhagem só fica gravada quando a publicação sai pelo publicador.`
                : " Etiquetas gravadas no momento da publicação."}
            </p>
            {pub.url && <a className="text-primary underline-offset-4 hover:underline" href={pub.url} target="_blank" rel="noreferrer">Abrir na plataforma</a>}
          </div>
          <section aria-label="Fotografias por idade">
            <h3 className="mb-1 font-medium">Fotografias por idade</h3>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
              {AGES.map((a) => {
                const s = pub.snapshots[a];
                return (
                  <div key={a} className="contents">
                    <dt className="text-muted-foreground">{AGE_LABEL[a]}</dt>
                    <dd>{s ? <>{new Intl.NumberFormat("pt-PT").format(s.views ?? 0)} views · <Idx value={s.idx} reason={idxMissingReason(s, center.params.min_base)} /></>
                      : <span className="text-muted-foreground">Sem leitura nessa idade</span>}</dd>
                  </div>
                );
              })}
            </dl>
          </section>
          <section aria-label="Etiquetas da publicação">
            <h3 className="mb-1 font-medium">Etiquetas</h3>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
              <Tag label="Conteúdo" value={pub.content_id ? `${pub.content_id}${pub.version_no ? ` · versão ${pub.version_no}` : ""}` : null} />
              <Tag label="Formato" value={pub.formato} />
              <Tag label="Máquina" value={pub.maquina} />
              <Tag label="Tema" value={pub.tema} />
              <Tag label="Hook" value={pub.hook_text ? `${pub.hook_index != null ? `Hook ${pub.hook_index + 1}: ` : ""}${pub.hook_text}` : null} />
              <Tag label="Mecanismo do hook" value={pub.hook_mechanism ? MECHANISM_LABEL[pub.hook_mechanism] ?? pub.hook_mechanism : null} />
              <Tag label="Estilo de edição" value={pub.edit_style_key ? `${pub.edit_style_key} v${pub.edit_style_version}` : null} />
              <Tag label="Frase-persona" value={pub.persona_phrase} />
              <Tag label="Duração" value={pub.duration_s != null ? `${Math.round(pub.duration_s)} s` : null} />
              <Tag label="Tipo de fonte" value={pub.source_type ? SOURCE_LABEL[pub.source_type] ?? pub.source_type : null} />
              <Tag label="Geração" value={pub.generation == null ? null : pub.generation === 0 ? "Original" : `Republicação ${pub.generation}`} />
              <Tag label="Camada" value={pub.tier ? TIER_LABEL[pub.tier] ?? pub.tier : null} />
              <Tag label="Hora local" value={pub.local_hour != null ? `${String(pub.local_hour).padStart(2, "0")}h` : null} />
            </dl>
          </section>
          <section aria-label="Ressonância">
            <h3 className="mb-1 font-medium">Ressonância (última leitura)</h3>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
              <Tag label="Comentários por 1.000" value={fmtPerK(pub.comments_pk)} />
              <Tag label="Gostos por 1.000" value={fmtPerK(pub.likes_pk)} />
              <Tag label="Partilhas por 1.000" value={pub.shares_pk != null ? fmtPerK(pub.shares_pk) : "Sem partilhas nesta recolha"} />
              <dt className="text-muted-foreground">Guardados, retenção, alcance</dt><dd className="text-muted-foreground">{UNAVAILABLE}</dd>
            </dl>
          </section>
          {center.can_manage && <OriginForm access={access} pub={pub} onDone={onChanged} />}
        </div>
      </SheetContent>
    </Sheet>
  );
}

export function PerfPublications({ access, center }: { access: Access; center: PerfCenter }) {
  const [account, setAccount] = useState("");
  const [origin, setOriginF] = useState<"" | "sistema" | "externo">("");
  const [sort, setSort] = useState<"recentes" | "indice">("recentes");
  const [page, setPage] = useState(0);
  const [open, setOpen] = useState<Publication | null>(null);
  const [rev, setRev] = useState(0);
  const f: PerfFilters = { account: account || undefined, origin: origin || undefined, sort, limit: PAGE, offset: page * PAGE };
  const { data, error, loading, reload } = useLoad(() => fetchPublications(access, f), `${access.ws}|${JSON.stringify(f)}|${rev}`);
  const tz = center.client.timezone;
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-end gap-3">
        <Field id="pub-account" label="Conta">
          <select id="pub-account" className={selectClass} value={account} onChange={(e) => { setAccount(e.target.value); setPage(0); }}>
            <option value="">Todas as contas</option>
            {center.accounts.map((a) => <option key={a.id} value={a.id}>@{a.handle} · {a.platform}</option>)}
          </select>
        </Field>
        <Field id="pub-origin" label="Origem">
          <select id="pub-origin" className={selectClass} value={origin} onChange={(e) => { setOriginF(e.target.value as typeof origin); setPage(0); }}>
            <option value="">Todas</option><option value="sistema">Só o que fizemos (sistema)</option><option value="externo">Externas</option>
          </select>
        </Field>
        <Field id="pub-sort" label="Ordenar">
          <select id="pub-sort" className={selectClass} value={sort} onChange={(e) => { setSort(e.target.value as typeof sort); setPage(0); }}>
            <option value="recentes">Mais recentes</option><option value="indice">Índice às 72 h</option>
          </select>
        </Field>
      </div>
      <LoadState loading={loading} error={error} reload={reload} label="as publicações">
        {data && data.items.length === 0 ? (
          <p className="rounded-md border p-6 text-center text-sm text-muted-foreground">
            {origin === "sistema" ? "Ainda não há publicações com origem sistema: nada saiu pelo publicador e nenhuma importada foi corrigida." : "Ainda não há publicações guardadas para estes filtros."}
          </p>
        ) : data && (
          <Card className="shadow-none dark:ring-0">
            <CardContent className="px-0">
              <div className="overflow-x-auto">
                <Table aria-label="Publicações">
                  <TableHeader>
                    <TableRow>
                      <TableHead className="min-w-56">Publicação</TableHead>
                      <TableHead>Origem</TableHead>
                      {AGES.map((a) => <TableHead key={a} className="whitespace-nowrap text-right">{AGE_LABEL[a]}</TableHead>)}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.items.map((p) => (
                      <TableRow key={`${p.account_id}/${p.reel_id}`} data-reel={p.reel_id}>
                        <TableCell className="max-w-72">
                          <button type="button" className="line-clamp-2 text-left font-medium hover:underline" onClick={() => setOpen(p)}>{p.title}</button>
                          <div className="text-xs text-muted-foreground">@{p.handle} · {p.platform} · {dateTime(p.published_at, tz) || "sem data"}{p.formato ? ` · ${p.formato}` : ""}</div>
                        </TableCell>
                        <TableCell><OriginBadge origin={p.origin} /></TableCell>
                        {AGES.map((a) => {
                          const s = p.snapshots[a];
                          return (
                            <TableCell key={a} className="whitespace-nowrap text-right">
                              <Idx value={s?.idx} reason={s ? (s.base_n ?? 0) < center.params.min_base ? "amostra curta" : "sem índice" : "sem leitura"} />
                            </TableCell>
                          );
                        })}
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )}
        {data && data.total > PAGE && (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Button size="sm" variant="outline" disabled={page === 0} onClick={() => setPage((n) => n - 1)}>Anteriores</Button>
            <span>{page * PAGE + 1} a {Math.min(data.total, (page + 1) * PAGE)} de {data.total}</span>
            <Button size="sm" variant="outline" disabled={(page + 1) * PAGE >= data.total} onClick={() => setPage((n) => n + 1)}>Seguintes</Button>
          </div>
        )}
      </LoadState>
      {open && <Details access={access} pub={open} center={center} onClose={() => setOpen(null)} onChanged={() => { setRev((n) => n + 1); }} />}
    </div>
  );
}
