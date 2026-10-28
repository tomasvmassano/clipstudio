"use client";

import { useId } from "react";
import { ExternalLinkIcon } from "lucide-react";
import { Area, AreaChart, Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart";
import { ShareBarList, ShareBarListContent, ShareBarListFill, ShareBarListItem, ShareBarListLabel, ShareBarListValue } from "@/components/share-bar-list";
import { FORMATO_LABEL } from "@/lib/types";
import { fmtCompact, fmtDay, fmtInt, type Desempenho, type ReelRow } from "@/lib/desempenho";

const viewsConfig = { views: { label: "Views", color: "var(--chart-2)" } } satisfies ChartConfig;
const diasConfig = {
  validados: { label: "Validados", color: "var(--chart-2)" },
  gravados: { label: "Gravados", color: "var(--chart-1)" },
  rejeitados: { label: "Rejeitados", color: "var(--chart-5)" },
} satisfies ChartConfig;

export function KpiCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="dark:bg-transparent">
      <CardHeader className="pb-0">
        <CardDescription>{label}</CardDescription>
        <CardTitle className="font-mono text-2xl tabular-nums">{value}</CardTitle>
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{hint}</CardContent>
    </Card>
  );
}

export function ViewsPorSemana({ d }: { d: Desempenho }) {
  const gid = `views-${useId().replace(/:/g, "")}`;
  const data = d.semanas.map((s) => ({ ...s, label: fmtDay(s.semana) }));
  return (
    <Card className="md:col-span-2 lg:col-span-3 dark:bg-transparent">
      <CardHeader className="flex flex-row items-start justify-between">
        <div className="flex flex-col gap-1.5">
          <CardTitle className="font-mono text-2xl tabular-nums">{fmtCompact(d.kpi.views)}</CardTitle>
          <CardDescription className="text-pretty">Views dos {fmtInt(d.kpi.reels)} reels guardados, por semana de publicação.</CardDescription>
        </div>
      </CardHeader>
      <CardContent>
        <ChartContainer className="aspect-auto h-60 w-full" config={viewsConfig}>
          <AreaChart accessibilityLayer data={data} margin={{ left: 12, right: 12 }}>
            <defs>
              <linearGradient id={gid} x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" stopColor="var(--color-views)" stopOpacity={0.35} />
                <stop offset="100%" stopColor="var(--color-views)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} />
            <XAxis axisLine={false} dataKey="label" tickLine={false} tickMargin={8} />
            <ChartTooltip
              content={<ChartTooltipContent indicator="dashed" formatter={(v, _n, item) => <span className="tabular-nums">{fmtCompact(Number(v))} views · {item.payload.n} reels</span>} />}
              cursor={{ stroke: "var(--color-views)", strokeDasharray: "3 3" }}
              wrapperStyle={{ outline: "none" }}
            />
            <Area dataKey="views" dot={{ fill: "var(--color-views)", r: 2.5, strokeWidth: 2 }} fill={`url(#${gid})`} isAnimationActive={false} stroke="var(--color-views)" strokeWidth={2} type="linear" />
          </AreaChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}

export function Referencias({ d }: { d: Desempenho }) {
  const max = Math.max(d.kpi.mediana ?? 0, ...d.referencias.map((r) => r.mediana));
  const rows = [{ owner: "itsnumeiro (cliente)", mediana: d.kpi.mediana ?? 0, melhor: 0, n: d.kpi.reels, me: true }, ...d.referencias.map((r) => ({ ...r, me: false }))]
    .sort((x, y) => y.mediana - x.mediana);
  return (
    <Card className="dark:bg-transparent">
      <CardHeader>
        <CardTitle>Mediana de views</CardTitle>
        <CardDescription className="text-pretty">Cliente vs criadores de referência (top reels scrapeados).</CardDescription>
      </CardHeader>
      <CardContent className="px-3">
        <ShareBarList>
          {rows.map((r) => (
            <ShareBarListItem key={r.owner} value={max ? (r.mediana / max) * 100 : 0} className={r.me ? "font-semibold" : ""}>
              <ShareBarListFill />
              <ShareBarListContent>
                <ShareBarListLabel>{r.owner}</ShareBarListLabel>
                <ShareBarListValue>{fmtCompact(r.mediana)}</ShareBarListValue>
              </ShareBarListContent>
            </ShareBarListItem>
          ))}
        </ShareBarList>
      </CardContent>
    </Card>
  );
}

function ReelTable({ rows, title, desc, showDate }: { rows: ReelRow[]; title: string; desc: string; showDate?: boolean }) {
  return (
    <Card className="md:col-span-2 dark:bg-transparent">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription className="text-pretty">{desc}</CardDescription>
      </CardHeader>
      <CardContent className="p-0 pb-2">
        <Table className="border-t">
          <TableHeader>
            <TableRow>
              <TableHead className="pl-6">Reel</TableHead>
              <TableHead className="text-end">Views</TableHead>
              <TableHead className="text-end">Outlier</TableHead>
              <TableHead className="pr-6 text-end">{showDate ? "Data" : "Coment."}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.id} className="hover:bg-transparent">
                <TableCell className="max-w-[260px] truncate pl-6">
                  <a href={r.url ?? `https://www.instagram.com/reel/${r.id}/`} target="_blank" rel="noopener" className="inline-flex max-w-full items-center gap-1 underline-offset-2 hover:underline">
                    <span className="truncate">{r.titulo?.trim() || r.id}</span>
                    <ExternalLinkIcon className="size-3 shrink-0 text-muted-foreground" />
                  </a>
                </TableCell>
                <TableCell className="text-end text-xs tabular-nums text-muted-foreground">{fmtCompact(r.views)}</TableCell>
                <TableCell className="text-end text-xs tabular-nums">
                  {r.outlier != null && (
                    <Badge variant={r.outlier >= 2 ? "default" : "outline"} className="tabular-nums">{r.outlier.toFixed(1)}×</Badge>
                  )}
                </TableCell>
                <TableCell className="pr-6 text-end text-xs tabular-nums text-muted-foreground">{showDate ? fmtDay(r.dt) : fmtInt(r.comments)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export function TopReels({ d }: { d: Desempenho }) {
  return <ReelTable rows={d.top} title="Reels com mais views" desc="Outlier = views a dividir pela mediana do criador. 2× ou mais conta como viral." />;
}
export function Recentes({ d }: { d: Desempenho }) {
  return <ReelTable rows={d.recentes} title="Últimos publicados" desc="Os 10 mais recentes guardados pelo scraper." showDate />;
}

export function Formatos({ d }: { d: Desempenho }) {
  const max = Math.max(1, ...d.formatos.map((f) => f.n));
  return (
    <Card className="dark:bg-transparent">
      <CardHeader>
        <CardTitle>Guiões por formato</CardTitle>
        <CardDescription className="text-pretty">Mix gerado pelo motor. Os validados mostram o que o Creator aceita.</CardDescription>
      </CardHeader>
      <CardContent className="px-3">
        <ShareBarList>
          {d.formatos.map((f) => (
            <ShareBarListItem key={f.formato ?? "?"} value={(f.n / max) * 100}>
              <ShareBarListFill />
              <ShareBarListContent>
                <ShareBarListLabel>{FORMATO_LABEL[f.formato ?? ""] ?? f.formato ?? "sem formato"}</ShareBarListLabel>
                <ShareBarListValue>{f.n}<span className="ml-1 text-xs font-normal text-muted-foreground">({f.validados} val.)</span></ShareBarListValue>
              </ShareBarListContent>
            </ShareBarListItem>
          ))}
        </ShareBarList>
      </CardContent>
    </Card>
  );
}

export function Producao({ d }: { d: Desempenho }) {
  const data = d.dias.map((x) => ({ ...x, label: fmtDay(x.date) }));
  return (
    <Card className="md:col-span-2 dark:bg-transparent">
      <CardHeader>
        <CardTitle>Produção dos últimos 30 dias</CardTitle>
        <CardDescription className="text-pretty">Guiões validados, gravados e rejeitados por dia.</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer className="aspect-auto h-48 w-full" config={diasConfig}>
          <BarChart accessibilityLayer data={data} margin={{ left: 0, right: 12 }}>
            <CartesianGrid vertical={false} />
            <XAxis axisLine={false} dataKey="label" tickLine={false} tickMargin={8} />
            <YAxis axisLine={false} tickLine={false} width={28} allowDecimals={false} />
            <ChartTooltip content={<ChartTooltipContent />} wrapperStyle={{ outline: "none" }} />
            <Bar dataKey="validados" fill="var(--color-validados)" radius={3} isAnimationActive={false} />
            <Bar dataKey="gravados" fill="var(--color-gravados)" radius={3} isAnimationActive={false} />
            <Bar dataKey="rejeitados" fill="var(--color-rejeitados)" radius={3} isAnimationActive={false} />
          </BarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
