"use client";

import { useMemo } from "react";
import { ArrowRightLeftIcon, ScissorsIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { clipOrder, masterTime, type ClipGap, type ClipPiece } from "@/lib/clip-order";
import { fmtT, type EditDoc } from "@/lib/edit-doc";
import { cn } from "@/lib/utils";

/**
 * Original vs. cortado (CLIP-06, ADR-0073): à esquerda os trechos pela ordem do master (com os tempos do master e o que ficou
 * de fora), à direita a ordem do corte na versão aberta. Clicar num trecho leva a pré-visualização até ele. Só leitura; só
 * aparece quando o documento tem ai.clip (veio do Clip Miner).
 */
export function ClipOrderView({ doc, t, onSeek }: { doc: EditDoc; t: number; onSeek: (t: number) => void }) {
  const r = useMemo(() => clipOrder(doc), [doc]);
  if (r === null) return null;
  return (
    <section className="flex flex-col gap-3 rounded-lg border p-3 text-sm" aria-labelledby="clip-order-h" data-testid="clip-order">
      <div className="flex flex-wrap items-center gap-2">
        <ArrowRightLeftIcon className="size-4 text-muted-foreground" aria-hidden />
        <h2 id="clip-order-h" className="font-medium">Original vs. cortado</h2>
        {typeof r !== "string" && (
          <>
            <Badge variant="outline">{r.moved} {r.moved === 1 ? "movido" : "movidos"}</Badge>
            <Badge variant="outline">{r.removed} {r.removed === 1 ? "cortado" : "cortados"}</Badge>
          </>
        )}
      </div>
      {typeof r === "string" ? (
        <Alert variant="destructive"><AlertDescription>Não dá para comparar com o original: {r} Abre outra versão no seletor de versões ou repõe a versão 1 do Clip Miner.</AlertDescription></Alert>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            Trecho do master {masterTime(r.span.in)}-{masterTime(r.span.out)}.
            {r.info.reordered ? ` A IA passou o gancho para o início (${r.info.parts.length} trechos de frases inteiras).` : " A IA não reordenou este corte."}
            {" "}Clica num trecho para o ver na pré-visualização.
          </p>
          {r.unchanged && <p className="text-xs" role="status">Mesma ordem do master e nada cortado dentro do trecho.</p>}
          <div className="grid gap-3 md:grid-cols-2">
            <div className="min-w-0">
              <h3 className="mb-1 text-xs font-medium text-muted-foreground">Original (ordem do master)</h3>
              <ol className="flex flex-col gap-1" aria-label="Original, pela ordem do master">
                {r.original.map((x) => x.kind === "cut"
                  ? <GapRow key={`cut-${x.in}`} g={x} />
                  : <PieceRow key={`o-${x.id}`} p={x} t={t} onSeek={onSeek} side="original" />)}
              </ol>
            </div>
            <div className="min-w-0">
              <h3 className="mb-1 text-xs font-medium text-muted-foreground">Cortado (versão aberta)</h3>
              <ol className="flex flex-col gap-1" aria-label="Cortado, pela ordem em que se ouve">
                {r.cut.map((p) => <PieceRow key={`c-${p.id}-${p.outIndex}`} p={p} t={t} onSeek={onSeek} side="cut" />)}
              </ol>
            </div>
          </div>
        </>
      )}
    </section>
  );
}

function PieceRow({ p, t, onSeek, side }: { p: ClipPiece; t: number; onSeek: (t: number) => void; side: "original" | "cut" }) {
  const here = t >= p.at && t < p.at + p.dur;
  const flag = p.moved || p.repeated;
  const n = side === "original" ? p.rank : p.outIndex;
  return (
    <li>
      <button type="button" onClick={() => onSeek(p.at)} aria-current={here ? "true" : undefined}
        aria-label={`Trecho ${n}, ${masterTime(p.in)} a ${masterTime(p.out)} no master, ${p.change}. Ir para ${fmtT(p.at)} na pré-visualização`}
        className={cn("flex w-full min-w-0 flex-col gap-0.5 rounded-md border px-2 py-1.5 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
          flag && "border-amber-500/60", here && "bg-muted")}>
        <span className="flex flex-wrap items-center gap-x-2 text-xs">
          <span className="font-medium tabular-nums">{n}.º</span>
          <span className="tabular-nums text-muted-foreground">{masterTime(p.in)}-{masterTime(p.out)}</span>
          <span className={cn(flag ? "text-amber-500" : "text-muted-foreground")}>
            {flag && <ArrowRightLeftIcon className="mr-0.5 inline size-3" aria-hidden />}{p.change}
          </span>
        </span>
        {p.text && <span className="truncate text-xs">{p.text}</span>}
      </button>
    </li>
  );
}

function GapRow({ g }: { g: ClipGap }) {
  return (
    <li className="flex min-w-0 flex-col gap-0.5 rounded-md border border-dashed border-destructive/60 px-2 py-1.5 text-xs"
      aria-label={`${g.change}, fora do corte, sem posição na pré-visualização`}>
      <span className="flex items-center gap-1 text-destructive"><ScissorsIcon className="size-3" aria-hidden />{g.change}</span>
      {g.text && <span className="truncate text-muted-foreground line-through">{g.text}</span>}
    </li>
  );
}
