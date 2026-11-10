"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { SearchIcon, UploadIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import type { MediaAsset } from "@/lib/media";

/**
 * Escolher uma imagem da Biblioteca pela miniatura (W10-37): grelha com procura; ao abrir pede os links das imagens (ensure) e
 * mostra cada uma quando chega. onPick devolve o ativo escolhido.
 */
export function ImagePicker({ open, onOpenChange, images, urls, ensure, onPick, onFiles, title }: {
  open: boolean; onOpenChange: (o: boolean) => void; images: MediaAsset[]; urls: Record<string, string>;
  ensure: (ids: string[]) => void; onPick: (a: MediaAsset) => void; title: string;
  /** Imagens do computador (W10-38): vão para a Biblioteca e entram no vídeo. */
  onFiles?: (files: File[]) => void;
}) {
  const [q, setQ] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);
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
        {onFiles && (
          <div className={over ? "flex flex-wrap items-center gap-2 rounded-md border-2 border-dashed border-primary p-3" : "flex flex-wrap items-center gap-2 rounded-md border-2 border-dashed p-3"}
            onDragOver={(e) => { if (e.dataTransfer?.types.includes("Files")) { e.preventDefault(); setOver(true); } }}
            onDragLeave={() => setOver(false)}
            onDrop={(e) => { e.preventDefault(); setOver(false); const fs = Array.from(e.dataTransfer?.files ?? []); if (fs.length) onFiles(fs); }}>
            <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()}><UploadIcon /> Carregar do computador</Button>
            <span className="text-xs text-muted-foreground">ou arrasta imagens para aqui (ficam também na Biblioteca)</span>
            <input ref={fileRef} type="file" accept="image/*" multiple className="hidden"
              onChange={(e) => { const fs = Array.from(e.target.files ?? []); e.target.value = ""; if (fs.length) onFiles(fs); }} />
          </div>
        )}
        <label className="relative">
          <SearchIcon className="pointer-events-none absolute left-2 top-2.5 size-4 text-muted-foreground" aria-hidden />
          <Input className="pl-8" placeholder="Procurar pelo nome ou etiqueta" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Procurar imagens" />
        </label>
        {images.length === 0 ? (
          <p className="text-sm text-muted-foreground">Ainda não há imagens na Biblioteca deste cliente. Carrega do computador aqui em cima.</p>
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
