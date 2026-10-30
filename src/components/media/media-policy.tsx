"use client";

import { useState } from "react";
import { Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { fmtDateTime } from "@/components/media/media-shared";
import type { Access } from "@/lib/access";
import { savePolicy, type MediaLibrary } from "@/lib/media";
import { bytes } from "@/lib/media-format";

/* Tipos, tamanho máximo, quota e lixo por cliente (FR-08-05). Só o dono da agência (media.policy.manage). */

const ALL_MIME: { mime: string; label: string }[] = [
  { mime: "video/mp4", label: "Vídeo MP4" }, { mime: "video/quicktime", label: "Vídeo MOV" }, { mime: "video/webm", label: "Vídeo WebM" },
  { mime: "audio/mpeg", label: "Áudio MP3" }, { mime: "audio/mp4", label: "Áudio M4A" }, { mime: "audio/aac", label: "Áudio AAC" },
  { mime: "audio/wav", label: "Áudio WAV" }, { mime: "audio/x-wav", label: "Áudio WAV (x-wav)" }, { mime: "audio/webm", label: "Áudio WebM" },
  { mime: "image/png", label: "PNG" }, { mime: "image/jpeg", label: "JPEG" }, { mime: "image/webp", label: "WebP" }, { mime: "image/gif", label: "GIF" },
  { mime: "text/vtt", label: "Legendas VTT" }, { mime: "application/x-subrip", label: "Legendas SRT" }, { mime: "text/plain", label: "Texto" },
  { mime: "application/pdf", label: "PDF" }, { mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", label: "Word (DOCX)" },
];
const MB = 1048576; const GB = 1073741824;

export function MediaPolicySheet({ access, d, onClose, onChanged }: { access: Access; d: MediaLibrary; onClose: () => void; onChanged: () => void }) {
  const p = d.policy;
  const [mimes, setMimes] = useState<string[]>(p.allowed_mime);
  const [maxMb, setMaxMb] = useState(String(Math.round(p.max_file_bytes / MB)));
  const [quotaGb, setQuotaGb] = useState(String(Math.round((p.quota_bytes / GB) * 100) / 100));
  const [days, setDays] = useState(String(p.trash_days));
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad: boolean } | null>(null);
  const run = async (fields: Parameters<typeof savePolicy>[1]) => {
    setBusy(true); setMsg(null);
    try { await savePolicy(access, fields); setMsg({ text: "Guardado.", bad: false }); onChanged(); }
    catch (e) { setMsg({ text: (e as Error).message, bad: true }); } finally { setBusy(false); }
  };
  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>Tipos, tamanho e quota</SheetTitle>
          <SheetDescription>Regras da biblioteca deste cliente, verificadas no servidor em cada envio.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6 text-sm">
          <fieldset className="flex flex-col gap-1">
            <legend className="mb-1 font-semibold">Tipos permitidos</legend>
            <div className="grid grid-cols-2 gap-1">
              {ALL_MIME.map((m) => (
                <label key={m.mime} className="inline-flex items-center gap-2">
                  <input type="checkbox" checked={mimes.includes(m.mime)} onChange={() => setMimes((s) => (s.includes(m.mime) ? s.filter((x) => x !== m.mime) : [...s, m.mime]))} />
                  {m.label}
                </label>
              ))}
            </div>
          </fieldset>
          <label className="flex flex-col gap-1">Máximo por ficheiro (MB)
            <Input type="number" min={1} max={Math.floor(p.ceiling_bytes / MB)} value={maxMb} onChange={(e) => setMaxMb(e.target.value)} />
            <span className="text-xs text-muted-foreground">Até {bytes(p.ceiling_bytes)}: é o limite do armazenamento, que depende do plano do Supabase. Para subir, muda primeiro o plano e o limite do bucket &quot;media&quot;.</span>
          </label>
          <label className="flex flex-col gap-1">Quota total (GB)
            <Input type="number" min={0.1} step={0.1} value={quotaGb} onChange={(e) => setQuotaGb(e.target.value)} />
            <span className="text-xs text-muted-foreground">Inclui o que está no lixo e os órfãos até serem limpos.</span>
          </label>
          <label className="flex flex-col gap-1">Dias no lixo antes de poder ser apagado
            <Input type="number" min={1} max={365} value={days} onChange={(e) => setDays(e.target.value)} />
          </label>
          <p className="text-xs text-muted-foreground">Antivírus: não há serviço ligado, os ficheiros não são analisados (decisão em aberto).</p>
          {p.updated_at && <p className="text-xs text-muted-foreground">Última mudança: {p.updated_label ?? "?"}, {fmtDateTime(p.updated_at, d.timezone)}</p>}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={busy || mimes.length === 0} onClick={() => void run({
              allowed_mime: mimes, max_file_bytes: Math.round(Number(maxMb) * MB), quota_bytes: Math.round(Number(quotaGb) * GB), trash_days: Math.round(Number(days)),
            })}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button>
            {p.customized && <Button size="sm" variant="ghost" disabled={busy}
              onClick={() => void run({ allowed_mime: null, max_file_bytes: null, quota_bytes: null, trash_days: null })}>Repor valores por defeito</Button>}
          </div>
          {msg && <p role={msg.bad ? "alert" : "status"} className={msg.bad ? "text-destructive" : ""}>{msg.text}</p>}
        </div>
      </SheetContent>
    </Sheet>
  );
}
