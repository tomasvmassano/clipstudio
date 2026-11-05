"use client";

import { useCallback, useEffect, useState } from "react";
import { HistoryIcon, Loader2Icon, PlusIcon, RotateCwIcon, Trash2Icon, UserRoundIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import type { Access } from "@/lib/access";
import {
  fetchPersona, fetchPersonaVersion, newPersonaId, personaProblem, savePersona, type PersonaList, type PersonaPhrase,
} from "@/lib/persona";

const when = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

/** Frases-persona (R-17): a única hipérbole sobre o criador que os agentes podem usar. Ler: agents.read; gerir: persona.manage. */
export function PersonaPhrases({ access }: { access: Access }) {
  const [d, setD] = useState<PersonaList | null>(null);
  const [draft, setDraft] = useState<PersonaPhrase[] | null>(null);
  const [note, setNote] = useState("");
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState<{ text: string; ok: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [old, setOld] = useState<{ version: number; phrases: PersonaPhrase[] } | null>(null);

  const load = useCallback(async () => {
    try { const x = await fetchPersona(access); setD(x); setDraft(null); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => { const t = setTimeout(() => void load(), 0); return () => clearTimeout(t); }, [load]);

  if (err) return <Alert variant="destructive"><AlertDescription>{err} <Button size="sm" variant="link" onClick={() => void load()}>Tentar de novo</Button></AlertDescription></Alert>;
  if (!d) return <Skeleton className="h-48" />;

  const list = draft ?? d.phrases;
  const dirty = draft !== null && JSON.stringify(draft) !== JSON.stringify(d.phrases);
  const problem = dirty ? personaProblem(list) : null;
  const edit = (f: (l: PersonaPhrase[]) => PersonaPhrase[]) => setDraft(f(structuredClone(list)));
  const set = (i: number, p: Partial<PersonaPhrase>) => edit((l) => { l[i] = { ...l[i], ...p }; return l; });

  const save = async () => {
    setBusy(true); setMsg(null);
    try {
      const x = await savePersona(access, list, d.version, note);
      setD(x); setDraft(null); setNote("");
      setMsg({ text: `Versão ${x.version} gravada. As próximas execuções dos agentes usam esta lista.`, ok: true });
    } catch (e) {
      const c = (e as Error & { code?: string }).code;
      setMsg({ text: (e as Error).message, ok: false });
      if (c === "40001") void fetchPersona(access).then(setD).catch(() => {});
    } finally { setBusy(false); }
  };

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_18rem]">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Frases-persona {d.version > 0 && <Badge variant="outline" className="ml-2">versão {d.version}</Badge>}</CardTitle>
          <CardDescription>
            Hipérbole sobre o próprio criador (ex.: &ldquo;o homem mais rico de Portugal&rdquo;) só pode aparecer em hooks e títulos se estiver nesta lista.
            Não é afirmação factual. Continuam proibidas acusações a terceiros identificados, notícias inventadas, números apresentados como dados e promessas de ganhos.
            Pessoas reais famosas só aparecem nas frases aprovadas aqui.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          {list.length === 0 && <p className="text-muted-foreground">Ainda sem frases. Sem lista, os agentes não usam hipérbole de persona.</p>}
          {list.map((p, i) => (
            <div key={p.id} className="flex flex-col gap-2 rounded-md border p-2">
              <div className="flex items-center gap-2">
                <Input aria-label={`Frase ${i + 1}`} value={p.text} maxLength={160} disabled={!d.can.manage} onChange={(e) => set(i, { text: e.target.value })} />
                {d.can.manage && (
                  <>
                    <Button size="sm" variant={p.involves ? "secondary" : "ghost"} title="Esta frase envolve outra pessoa"
                      onClick={() => set(i, { involves: p.involves ? null : { name: "", consent_by: "", consent_at: "" } })}>
                      <UserRoundIcon /> <span className="sr-only sm:not-sr-only">Outra pessoa</span>
                    </Button>
                    <Button size="icon-sm" variant="ghost" aria-label={`Tirar a frase ${i + 1}`} onClick={() => edit((l) => l.filter((_, k) => k !== i))}><Trash2Icon /></Button>
                  </>
                )}
              </div>
              {p.involves && (
                <div className="grid gap-2 rounded bg-muted/50 p-2 sm:grid-cols-3">
                  <label className="flex flex-col gap-1 text-xs">Quem é
                    <Input className="h-8" value={p.involves.name} disabled={!d.can.manage} maxLength={80} onChange={(e) => set(i, { involves: { ...p.involves!, name: e.target.value } })} />
                  </label>
                  <label className="flex flex-col gap-1 text-xs">Consentimento dado por
                    <Input className="h-8" value={p.involves.consent_by} disabled={!d.can.manage} maxLength={80} onChange={(e) => set(i, { involves: { ...p.involves!, consent_by: e.target.value } })} />
                  </label>
                  <label className="flex flex-col gap-1 text-xs">Em que dia
                    <Input className="h-8" type="date" value={p.involves.consent_at} disabled={!d.can.manage} onChange={(e) => set(i, { involves: { ...p.involves!, consent_at: e.target.value } })} />
                  </label>
                  <label className="flex flex-col gap-1 text-xs sm:col-span-3">Como (opcional)
                    <Input className="h-8" value={p.involves.consent_note ?? ""} disabled={!d.can.manage} maxLength={300} placeholder="ex.: por mensagem, guardada na pasta do cliente"
                      onChange={(e) => set(i, { involves: { ...p.involves!, consent_note: e.target.value } })} />
                  </label>
                </div>
              )}
            </div>
          ))}
          {d.can.manage ? (
            <>
              <Button size="sm" variant="outline" className="self-start" disabled={list.length >= 100}
                onClick={() => edit((l) => [...l, { id: newPersonaId(l), text: "" }])}><PlusIcon /> Juntar frase</Button>
              {dirty && (
                <div className="flex flex-col gap-2 border-t pt-3">
                  <Input aria-label="Nota da versão" value={note} maxLength={500} placeholder="Nota desta versão (opcional): ex.: aprovado pelo Numeiro por mensagem" onChange={(e) => setNote(e.target.value)} />
                  {problem && <p className="text-xs text-destructive" role="alert">{problem}</p>}
                  <div className="flex gap-2">
                    <Button size="sm" disabled={busy || !!problem} onClick={() => void save()}>{busy && <Loader2Icon className="animate-spin" />} Gravar versão {d.version + 1}</Button>
                    <Button size="sm" variant="ghost" disabled={busy} onClick={() => { setDraft(null); setNote(""); }}>Descartar</Button>
                  </div>
                </div>
              )}
            </>
          ) : <p className="text-xs text-muted-foreground">Só quem tem &ldquo;Aprovar frases-persona&rdquo; muda esta lista.</p>}
          {msg && <Alert variant={msg.ok ? "default" : "destructive"}><AlertDescription>{msg.text}</AlertDescription></Alert>}
        </CardContent>
      </Card>

      <Card className="h-fit">
        <CardHeader>
          <CardTitle className="flex items-center gap-1.5 text-base"><HistoryIcon className="size-4" /> Versões</CardTitle>
          <CardDescription>Cada gravação fica guardada. Os agentes registam a versão que usaram.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-xs">
          {d.history.length === 0 && <p className="text-muted-foreground">Nenhuma versão ainda.</p>}
          {d.history.map((h) => (
            <button key={h.version} type="button" className="flex flex-col items-start rounded border p-2 text-left hover:bg-muted"
              onClick={() => void fetchPersonaVersion(access, h.version).then((x) => setOld({ version: x.version, phrases: x.phrases })).catch((e: Error) => setMsg({ text: e.message, ok: false }))}>
              <span className="font-medium">v{h.version} · {h.count} {h.count === 1 ? "frase" : "frases"}{h.version === d.version ? " · em vigor" : ""}</span>
              <span className="text-muted-foreground">{h.by ?? "alguém"} · {when(h.at)}</span>
              {h.note && <span className="text-muted-foreground">&ldquo;{h.note}&rdquo;</span>}
            </button>
          ))}
          {old && (
            <div className="rounded border border-dashed p-2">
              <div className="mb-1 flex items-center justify-between font-medium">Versão {old.version}
                <Button size="xs" variant="ghost" onClick={() => setOld(null)}>Fechar</Button></div>
              <ul className="list-disc pl-4">{old.phrases.map((p) => <li key={p.id}>{p.text}{p.involves ? ` (com ${p.involves.name})` : ""}</li>)}</ul>
              {d.can.manage && old.version !== d.version && (
                <Button size="xs" variant="outline" className="mt-2" onClick={() => { setDraft(structuredClone(old.phrases)); setNote(`volta à versão ${old.version}`); setOld(null); }}>
                  <RotateCwIcon /> Usar como base
                </Button>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
