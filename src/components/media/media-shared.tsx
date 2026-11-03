"use client";

import { useState, type ReactNode } from "react";
import { FileAudioIcon, FileIcon, FileTextIcon, FileVideoIcon, ImageIcon, LinkIcon, Loader2Icon, SubtitlesIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import type { MediaKind } from "@/lib/media-format";

export const selectCls = "h-8 min-w-0 rounded-md border bg-background px-2 text-sm";

export function KindIcon({ kind, className }: { kind: MediaKind; className?: string }) {
  const p = { className: className ?? "size-5", "aria-hidden": true };
  switch (kind) {
    case "video": return <FileVideoIcon {...p} />;
    case "audio": return <FileAudioIcon {...p} />;
    case "imagem": case "thumbnail": return <ImageIcon {...p} />;
    case "legenda": return <SubtitlesIcon {...p} />;
    case "documento": return <FileTextIcon {...p} />;
    case "link_externo": return <LinkIcon {...p} />;
    default: return <FileIcon {...p} />;
  }
}

export const fmtDateTime = (iso: string | null | undefined, tz: string) =>
  iso ? new Date(iso).toLocaleString("pt-PT", { timeZone: tz, day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "-";

/** Confirmação explícita: para eliminar definitivamente é preciso escrever APAGAR (o servidor volta a exigir). */
export function ConfirmDialog({ open, title, description, confirmLabel, typed, onCancel, onConfirm, children }: {
  open: boolean; title: string; description: ReactNode; confirmLabel: string; typed?: boolean;
  onCancel: () => void; onConfirm: (typed: string) => Promise<void>; children?: ReactNode;
}) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const go = async () => {
    setBusy(true); setErr("");
    try { await onConfirm(text); setText(""); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v && !busy) { setText(""); setErr(""); onCancel(); } }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {children}
        {typed && (
          <label className="flex flex-col gap-1 text-sm">Escreve APAGAR para confirmar
            <Input value={text} onChange={(e) => setText(e.target.value)} autoComplete="off" aria-label="Confirmação" />
          </label>
        )}
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={onCancel} disabled={busy}>Cancelar</Button>
          <Button variant="destructive" onClick={() => void go()} disabled={busy || (typed && text !== "APAGAR")}>
            {busy && <Loader2Icon className="animate-spin" />} {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
