"use client";

import { useEffect, useMemo, useState } from "react";
import { SearchIcon } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import type { MediaAsset } from "@/lib/media";

/**
 * Escolher uma imagem da Biblioteca pela miniatura (W10-37): grelha com procura; ao abrir pede os links das imagens (ensure) e
 * mostra cada uma quando chega. onPick devolve o ativo escolhido.
 */
export function ImagePicker({ open, onOpenChange, images, urls, ensure, onPick, title }: {
  open: boolean; onOpenChange: (o: boolean) => void; images: MediaAsset[]; urls: Record<string, string>;
  ensure: (ids: string[]) => void; onPick: (a: MediaAsset) => void; title: string;
}) {
  const [q, setQ] = useState("");
  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return s ? images.filter((a) => [a.title, ...a.tags].some((x) => x.toLowerCase().includes(s))) : images;
  }, [images, q]);
  useEffect(() => { if (open) ensure(shown.slice(0, 60).map((a) => a.id)); }, [open, shown, ensure]);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>Escolhe a imagem. Entra no cursor até ao fim da frase; depois ajustas a duração na linha do tempo ou no painel.</DialogDescription>
        </DialogHeader>
        <label className="relative">
          <SearchIcon className="pointer-events-none absolute left-2 top-2.5 size-4 text-muted-foreground" aria-hidden />
          <Input className="pl-8" placeholder="Procurar pelo nome ou etiqueta" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Procurar imagens" />
        </label>
        {images.length === 0 ? (
          <p className="text-sm text-muted-foreground">Ainda não há imagens na Biblioteca deste cliente. Carrega-as na Biblioteca e volta aqui.</p>
        ) : shown.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhuma imagem com esse nome.</p>
        ) : (
          <ul className="grid max-h-[60vh] grid-cols-2 gap-2 overflow-y-auto sm:grid-cols-4" aria-label="Imagens da Biblioteca">
            {shown.map((a) => (
              <li key={a.id}>
                <button type="button" onClick={() => { onPick(a); onOpenChange(false); }}
                  className="flex w-full flex-col gap-1 rounded-md border p-1 text-left hover:border-primary focus-visible:border-primary">
                  <span className="flex aspect-square w-full items-center justify-center overflow-hidden rounded bg-muted">
                    {urls[a.id] ? (
                      // eslint-disable-next-line @next/next/no-img-element -- link assinado curto do R2
                      <img src={urls[a.id]} alt="" className="max-h-full max-w-full object-contain" loading="lazy" />
                    ) : <span className="text-[10px] text-muted-foreground">…</span>}
                  </span>
                  <span className="truncate text-xs">{a.title}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}
