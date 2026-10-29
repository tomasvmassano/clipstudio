"use client";

import { useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { Access } from "@/lib/access";
import { fetchBreakdown, fetchLevers, type BreakdownGroup, type PerfCenter } from "@/lib/perf";
import {
  AGE_LABEL, AGES, DIMENSION_LABEL, INSUFFICIENT, LEVER_LABEL, MECHANISM_LABEL, TIER_LABEL, fmtIdx, type Age, type Dimension,
} from "@/lib/perf-format";
import { Field, Idx, LoadState, selectClass, useLoad } from "@/components/perf/perf-shared";

/* PERF-06 (vistas por dimensão) e PERF-07 (alavancas e relatório semanal). Views absolutas só dentro de uma conta. */

const DIMS = Object.keys(DIMENSION_LABEL) as Dimension[];

function groupLabel(dim: Dimension | string, g: { key: string; label?: string | null }) {
  if (g.label) return g.label;
  if (dim === "tier") return TIER_LABEL[g.key] ?? g.key;
  if (dim === "hook") return MECHANISM_LABEL[g.key] ?? g.key;
  if (dim === "generation") return g.key === "0" ? "Original" : `Republicação ${g.key}`;
  if (dim === "origin") return g.key === "sistema" ? "Sistema" : "Externo";
  return g.key;
}

/** Barra do índice (1× = mediana da conta), com o número escrito: a cor nunca é a única informação. */
function IdxBar({ value }: { value: number | null }) {
  if (value == null) return null;
  const w = Math.min(100, (value / 3) * 100);
  return (
    <div className="relative h-2 w-full max-w-40 rounded bg-muted" aria-hidden="true">
      <div className="absolute inset-y-0 left-0 rounded bg-primary" style={{ width: `${w}%` }} />
      <div className="absolute inset-y-0 w-px bg-foreground/60" style={{ left: `${100 / 3}%` }} />
    </div>
  );
}

function GroupRow({ dim, g }: { dim: Dimension; g: BreakdownGroup }) {
  return (
    <li className="flex flex-col gap-1 border-b py-2 last:border-b-0" data-group={g.key}>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="min-w-0 break-words font-medium">{groupLabel(dim, g)}</span>
        <span className="text-sm"><Idx value={g.idx_median} reason={`${INSUFFICIENT} (${g.n_indexed} com índice)`} /></span>
      </div>
      <IdxBar value={g.idx_median} />
      <div className="text-xs text-muted-foreground">
        {g.n} publicações, {g.n_indexed} com índice{g.n_indexed ? ` · melhor ${fmtIdx(g.idx_best)}, pior ${fmtIdx(g.idx_worst)}` : ""}
        {g.views_median != null ? ` · mediana de ${new Intl.NumberFormat("pt-PT").format(g.views_median)} views nesta conta` : g.accounts > 1 ? ` · ${g.accounts} contas, views não se comparam entre contas` : ""}
        {dim === "tier" && g.repeat_n ? ` · repetidas de outra conta: ${g.repeat_n}, índice mediano ${fmtIdx(g.repeat_idx_median)}` : ""}
      </div>
      {dim === "content" && g.items && (
        <ul className="ml-3 flex flex-col gap-0.5 text-xs">
          {g.items.map((i) => (
            <li key={`${i.platform}/${i.reel_id}`}>
              @{i.handle} · {i.platform}{i.hook_index != null ? ` · hook ${i.hook_index + 1}` : ""}: <Idx value={i.idx} reason="sem índice" />
            </li>
          ))}
        </ul>
      )}
    </li>
  );
}

export function PerfViews({ access, onlySystem }: { access: Access; onlySystem: boolean }) {
  const [dim, setDim] = useState<Dimension>("account");
  const [age, setAge] = useState<Age>("72h");
  const f = onlySystem ? { origin: "sistema" as const } : {};
  const { data, error, loading, reload } = useLoad(() => fetchBreakdown(access, dim, age, f), `${access.ws}|${dim}|${age}|${onlySystem}`);
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-end gap-3">
        <Field id="view-dim" label="Ver por">
          <select id="view-dim" className={selectClass} value={dim} onChange={(e) => setDim(e.target.value as Dimension)}>
            {DIMS.map((d) => <option key={d} value={d}>{DIMENSION_LABEL[d]}</option>)}
          </select>
        </Field>
        <Field id="view-age" label="Idade">
          <select id="view-age" className={selectClass} value={age} onChange={(e) => setAge(e.target.value as Age)}>
            {AGES.map((a) => <option key={a} value={a}>{AGE_LABEL[a]}</option>)}
          </select>
        </Field>
      </div>
      <LoadState loading={loading} error={error} reload={reload} label="a vista">
        {data && (
          <Card className="shadow-none dark:ring-0">
            <CardHeader>
              <CardTitle>{DIMENSION_LABEL[data.dimension]} · índice às {AGE_LABEL[data.age]}</CardTitle>
              <CardDescription>
                Índice = views ÷ mediana da mesma conta nos 30 dias anteriores, na mesma idade (1× é o normal da conta).
                {data.unassigned ? ` ${data.unassigned} publicações sem esta etiqueta não entram.` : ""}
              </CardDescription>
            </CardHeader>
            <CardContent>
              {data.groups.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  {onlySystem ? "Sem publicações com origem sistema. Desliga \"Só o que fizemos\" para ver as externas como comparação." : "Ainda não há publicações com esta etiqueta."}
                </p>
              ) : (
                <ul aria-label={`Vista por ${DIMENSION_LABEL[data.dimension]}`}>{data.groups.map((g) => <GroupRow key={g.key} dim={data.dimension} g={g} />)}</ul>
              )}
            </CardContent>
          </Card>
        )}
      </LoadState>
    </div>
  );
}

export function PerfLevers({ access, center, onlySystem }: { access: Access; center: PerfCenter; onlySystem: boolean }) {
  const { data, error, loading, reload } = useLoad(() => fetchLevers(access, onlySystem), `${access.ws}|${onlySystem}`);
  const tz = center.client.timezone;
  const day = (iso: string) => new Date(iso).toLocaleDateString("pt-PT", { timeZone: tz, day: "numeric", month: "short" });
  return (
    <LoadState loading={loading} error={error} reload={reload} label="as alavancas">
      {data && (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card className="shadow-none dark:ring-0 lg:col-span-2">
            <CardHeader>
              <CardTitle>O que replicar</CardTitle>
              <CardDescription>
                Índice mediano às 72 h por atributo, nos últimos 90 dias. Só aparece com pelo menos {data.params.min_sample} publicações com índice
                (valor de partida, a calibrar). A proposta automática do mix da semana pelo motor ainda não está disponível; quando existir, nada muda sem aprovação humana.
              </CardDescription>
            </CardHeader>
            <CardContent>
              {data.levers.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  {data.only_system ? "Ainda não há publicações com origem sistema e índice às 72 h. Desliga \"Só o que fizemos\" para ver as externas como comparação." : "Ainda não há publicações com índice às 72 h."}
                </p>
              ) : (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
                  {Array.from(new Set(data.levers.map((l) => l.dimension))).map((d) => (
                    <section key={d} aria-label={LEVER_LABEL[d] ?? d}>
                      <h3 className="mb-1 text-sm font-medium">{LEVER_LABEL[d] ?? d}</h3>
                      <ul className="flex flex-col gap-1 text-sm">
                        {data.levers.filter((l) => l.dimension === d).map((l) => (
                          <li key={l.key} className="flex flex-wrap items-baseline justify-between gap-2" data-lever={`${d}:${l.key}`}>
                            <span className="min-w-0 break-words">{groupLabel(d, { key: l.key })}</span>
                            {l.shown ? <span><Idx value={l.idx_median} /> <span className="text-xs text-muted-foreground">em {l.n}</span></span>
                              : <span className="text-xs text-muted-foreground">{INSUFFICIENT} ({l.n} de {data.params.min_sample})</span>}
                          </li>
                        ))}
                      </ul>
                    </section>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
          <Card className="shadow-none dark:ring-0 lg:col-span-2">
            <CardHeader>
              <CardTitle>Relatório da semana</CardTitle>
              <CardDescription>Publicadas entre {day(data.week.from)} e {day(data.week.to)}, todas já com 72 h. {data.week.n} com índice.</CardDescription>
            </CardHeader>
            <CardContent className="grid grid-cols-1 gap-4 md:grid-cols-2">
              {(["top", "bottom"] as const).map((k) => (
                <section key={k} aria-label={k === "top" ? "Top 10" : "Piores 10"}>
                  <h3 className="mb-1 text-sm font-medium">{k === "top" ? "Top 10" : "Piores 10"}</h3>
                  {data.week[k].length === 0 ? <p className="text-sm text-muted-foreground">Sem publicações nesta semana.</p> : (
                    <ol className="flex list-decimal flex-col gap-1 pl-5 text-sm">
                      {data.week[k].map((p) => (
                        <li key={`${p.account_id}/${p.reel_id}`}>
                          <span className="break-words">{p.title}</span> <span className="text-xs text-muted-foreground">@{p.handle} · {p.platform}</span> <Idx value={p.idx72} />
                        </li>
                      ))}
                    </ol>
                  )}
                </section>
              ))}
              <section aria-label="Hooks vencedores por plataforma">
                <h3 className="mb-1 text-sm font-medium">Hooks vencedores por plataforma</h3>
                {Object.keys(data.week.hooks_by_platform).length === 0 ? <p className="text-sm text-muted-foreground">Sem hooks registados nesta semana.</p> : (
                  <ul className="flex flex-col gap-2 text-sm">
                    {Object.entries(data.week.hooks_by_platform).map(([pl, hs]) => (
                      <li key={pl}><span className="font-medium">{pl}</span>
                        <ul className="ml-3">{hs.map((h) => <li key={h.reel_id} className="break-words">{h.hook_text}{h.hook_mechanism ? ` (${MECHANISM_LABEL[h.hook_mechanism] ?? h.hook_mechanism})` : ""} <Idx value={h.idx72} /></li>)}</ul>
                      </li>
                    ))}
                  </ul>
                )}
              </section>
              <section aria-label="Estilos a cortar">
                <h3 className="mb-1 text-sm font-medium">Estilos a cortar</h3>
                <p className="text-sm text-muted-foreground">
                  {data.week.styles_to_cut.length === 0
                    ? `Nenhum estilo com ${data.params.min_sample} ou mais publicações abaixo de ${fmtIdx(data.params.cut_below)}. O estilo só é conhecido nas publicações com linhagem gravada.`
                    : null}
                </p>
                {data.week.styles_to_cut.length > 0 && (
                  <ul className="text-sm">{data.week.styles_to_cut.map((s) => <li key={s.key}>{s.key}: <Idx value={s.idx_median} /> em {s.n}</li>)}</ul>
                )}
              </section>
            </CardContent>
          </Card>
        </div>
      )}
    </LoadState>
  );
}
