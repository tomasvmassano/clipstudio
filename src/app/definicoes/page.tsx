"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { ArrowRightIcon, ImageUpIcon, Loader2Icon, RotateCwIcon, Trash2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { LogoIcon } from "@/components/logo";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { removeLogo, uploadLogo, useLogoUrl } from "@/lib/branding";
import { CURRENCIES, fetchSettings, TIMEZONES, updateClient, type ClientPatch, type Settings } from "@/lib/clients";
import { setWipLimit } from "@/lib/tasks";

/*
 * Definições do cliente (PRD M15). Geral, regras e atalhos para o que já tem casa própria
 * (agentes, templates, automações, equipa). Quem não pode mudar vê, mas não edita; o servidor decide.
 */

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm disabled:opacity-60";

export default function DefinicoesPage() {
  return <WorkspaceGate need="team.read">{(access) => <Definicoes access={access} />}</WorkspaceGate>;
}

function Definicoes({ access }: { access: Access }) {
  const { refresh, mode } = useSession();
  const [s, setS] = useState<Settings | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    let alive = true;
    fetchSettings(access.ws).then((x) => { if (alive) { setS(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access.ws, rev]);

  if (mode === "code") return <Alert><AlertDescription>As definições só abrem com conta própria.</AlertDescription></Alert>;
  if (err) {
    return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
      <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  }
  if (!s) return <Skeleton className="h-96" />;

  const save = async (patch: ClientPatch, ok: string) => {
    setMsg(null);
    try { const r = await updateClient(access.ws, patch); setS({ ...s, ...r }); setMsg({ ok: true, text: ok }); await refresh(); return true; }
    catch (e) { setMsg({ ok: false, text: (e as Error).message }); return false; }
  };

  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Definições</h1>
        <p className="text-sm text-muted-foreground">De {s.name}. {s.can.manage ? "As mudanças ficam no histórico com quem as fez." : "Só quem gere as definições deste cliente as pode mudar."}</p>
      </div>
      {msg && <Alert variant={msg.ok ? "default" : "destructive"}><AlertDescription className="flex items-center justify-between gap-2" role="status">{msg.text}
        <Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button></AlertDescription></Alert>}

      <General s={s} ws={access.ws} save={save} />
      <Rules s={s} access={access} save={save} onWip={(n) => setS({ ...s, wip_limit: n })} setMsg={setMsg} />
      <Card>
        <CardHeader><CardTitle className="text-base">Noutros sítios</CardTitle><CardDescription>Estas definições têm página própria.</CardDescription></CardHeader>
        <CardContent className="grid gap-2 sm:grid-cols-2">
          <Shortcut href="/agentes/configuracao" title="Agentes" detail={s.agent_config === "active" ? "Configuração ativa" : s.agent_config === "draft" ? "Configuração por terminar" : "Sem configuração"} show={s.can.agents} />
          <Shortcut href="/tarefas?tab=templates" title="Templates e checklists" detail={`${s.counts.templates} ativo${s.counts.templates === 1 ? "" : "s"}`} show={s.can.tasks} />
          <Shortcut href="/tarefas?tab=regras" title="Automações de tarefas" detail={`${s.counts.automacoes} ativa${s.counts.automacoes === 1 ? "" : "s"}`} show={s.can.tasks} />
          <Shortcut href="/equipa" title="Equipa e acessos" detail="Convidar, papéis, remover" show />
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle className="text-base">Administração</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-center justify-between gap-3 text-sm">
          <span className="text-muted-foreground">
            {s.can.archive ? "Arquivar corta o acesso de toda a equipa e pára a agenda dos agentes. Nada é apagado." : "Só o dono da agência pode arquivar este cliente."}
          </span>
          {s.can.archive && <Button size="sm" variant="outline" nativeButton={false} render={<Link href="/clientes" />}>Arquivar em Clientes</Button>}
        </CardContent>
      </Card>
    </div>
  );
}

function Shortcut({ href, title, detail, show }: { href: string; title: string; detail: string; show: boolean }) {
  if (!show) return null;
  return (
    <Link href={href} className="flex items-center justify-between gap-2 rounded-md border p-3 text-sm hover:bg-muted">
      <span><b>{title}</b><span className="block text-xs text-muted-foreground">{detail}</span></span>
      <ArrowRightIcon className="size-4 text-muted-foreground" />
    </Link>
  );
}

function General({ s, ws, save }: { s: Settings; ws: string; save: (p: ClientPatch, ok: string) => Promise<boolean> }) {
  const [v, setV] = useState({ name: s.name, handle: s.handle ?? "", timezone: s.timezone, currency: s.currency, color: s.brand_color ?? "" });
  const [busy, setBusy] = useState<"" | "save" | "logo">("");
  const [logoErr, setLogoErr] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const logo = useLogoUrl(s.logo_path);
  const dis = !s.can.manage;
  const tzs = TIMEZONES.includes(v.timezone) ? TIMEZONES : [v.timezone, ...TIMEZONES];
  const curs = CURRENCIES.includes(v.currency) ? CURRENCIES : [v.currency, ...CURRENCIES];
  const colorOk = v.color === "" || /^#[0-9a-fA-F]{6}$/.test(v.color);

  return (
    <Card>
      <CardHeader><CardTitle className="text-base">Geral</CardTitle>
        <CardDescription>O fuso decide a hora dos prazos, do calendário e da corrida diária dos agentes. A app está em português de Portugal (é o único idioma por agora).</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-5">
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex size-16 items-center justify-center overflow-hidden rounded-lg border" style={{ backgroundColor: s.brand_color ?? undefined }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {logo ? <img src={logo} alt={`Logótipo de ${s.name}`} className="size-full object-contain" /> : <LogoIcon className="size-7 text-muted-foreground" aria-hidden />}
          </div>
          {!dis && (
            <div className="flex flex-col gap-1">
              <div className="flex gap-2">
                <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" className="hidden" aria-label="Escolher logótipo" onChange={async (e) => {
                  const f = e.target.files?.[0]; e.target.value = "";
                  if (!f) return;
                  setBusy("logo"); setLogoErr("");
                  try {
                    const path = await uploadLogo(ws, f);
                    const old = s.logo_path;
                    if (await save({ logo_path: path }, "Logótipo atualizado.") && old) {
                      const w = await removeLogo(old);
                      if (w) setLogoErr(`O logótipo novo ficou; não consegui apagar o antigo (${w}).`);
                    }
                  } catch (x) { setLogoErr((x as Error).message); }
                  finally { setBusy(""); }
                }} />
                <Button size="sm" variant="outline" disabled={busy !== ""} onClick={() => file.current?.click()}>
                  {busy === "logo" ? <Loader2Icon className="animate-spin" /> : <ImageUpIcon />} {s.logo_path ? "Trocar logótipo" : "Carregar logótipo"}
                </Button>
                {s.logo_path && <Button size="sm" variant="ghost" disabled={busy !== ""} onClick={async () => {
                  setBusy("logo"); setLogoErr("");
                  const old = s.logo_path!;
                  if (await save({ logo_path: null }, "Logótipo removido.")) { const w = await removeLogo(old); if (w) setLogoErr(`Saiu do cliente, mas o ficheiro ficou guardado (${w}).`); }
                  setBusy("");
                }}><Trash2Icon /> Remover</Button>}
              </div>
              <span className="text-xs text-muted-foreground">PNG, JPG ou WebP até 500 KB. Só quem trabalha neste cliente o vê.</span>
              {logoErr && <span className="text-xs text-destructive" role="alert">{logoErr}</span>}
            </div>
          )}
        </div>

        <form className="grid gap-3 sm:grid-cols-2" onSubmit={async (e) => {
          e.preventDefault(); setBusy("save");
          const patch: ClientPatch = {};
          if (v.name.trim() !== s.name) patch.name = v.name.trim();
          if (v.handle.trim() !== (s.handle ?? "")) patch.handle = v.handle.trim();
          if (v.timezone !== s.timezone) patch.timezone = v.timezone;
          if (v.currency !== s.currency) patch.currency = v.currency;
          if ((v.color || null) !== s.brand_color) patch.brand_color = v.color ? v.color.toLowerCase() : null;
          await save(patch, "Definições guardadas.");
          setBusy("");
        }}>
          <label className="flex flex-col gap-1 text-sm">Nome<Input disabled={dis} value={v.name} maxLength={80} onChange={(e) => setV({ ...v, name: e.target.value })} /></label>
          <label className="flex flex-col gap-1 text-sm">@ principal<Input disabled={dis} value={v.handle} maxLength={31} onChange={(e) => setV({ ...v, handle: e.target.value })} placeholder="sem @" /></label>
          <label className="flex flex-col gap-1 text-sm">Fuso horário
            <select aria-label="Fuso horário" disabled={dis} className={selectCls} value={v.timezone} onChange={(e) => setV({ ...v, timezone: e.target.value })}>{tzs.map((t) => <option key={t} value={t}>{t.replace("_", " ")}</option>)}</select>
          </label>
          <label className="flex flex-col gap-1 text-sm">Moeda
            <select aria-label="Moeda" disabled={dis} className={selectCls} value={v.currency} onChange={(e) => setV({ ...v, currency: e.target.value })}>{curs.map((c) => <option key={c} value={c}>{c}</option>)}</select>
          </label>
          <label className="flex flex-col gap-1 text-sm">Cor da marca
            <span className="flex gap-2">
              <input type="color" aria-label="Escolher cor" disabled={dis} className="h-9 w-12 cursor-pointer rounded-md border bg-background p-1 disabled:opacity-60"
                value={colorOk && v.color ? v.color : "#000000"} onChange={(e) => setV({ ...v, color: e.target.value })} />
              <Input disabled={dis} value={v.color} maxLength={7} onChange={(e) => setV({ ...v, color: e.target.value })} placeholder="#rrggbb (opcional)" aria-invalid={!colorOk} />
            </span>
            {!colorOk && <span className="text-xs text-destructive">Formato #RRGGBB.</span>}
          </label>
          {!dis && <div className="flex items-end justify-end sm:col-span-2">
            <Button type="submit" disabled={busy !== "" || !colorOk || v.name.trim().length < 2}>{busy === "save" && <Loader2Icon className="animate-spin" />} Guardar</Button>
          </div>}
        </form>
      </CardContent>
    </Card>
  );
}

function Rules({ s, access, save, onWip, setMsg }: {
  s: Settings; access: Access; save: (p: ClientPatch, ok: string) => Promise<boolean>; onWip: (n: number | null) => void;
  setMsg: (m: { ok: boolean; text: string } | null) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [wip, setWip] = useState(s.wip_limit ? String(s.wip_limit) : "");
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">Regras</CardTitle></CardHeader>
      <CardContent className="flex flex-col gap-4 text-sm">
        <div className="flex items-start justify-between gap-4">
          <div>
            <b>Só se gravam guiões aprovados</b>
            <p className="text-muted-foreground">Guiões em revisão não entram no teleprompter nem se marcam como gravados.</p>
          </div>
          <Switch aria-label="Só se gravam guiões aprovados" checked={s.require_approval_to_record} disabled={!s.can.manage || busy}
            onCheckedChange={async (c) => { setBusy(true); await save({ require_approval_to_record: c }, c ? "A partir de agora só se gravam guiões aprovados." : "Já se podem gravar guiões em revisão."); setBusy(false); }} />
        </div>
        <form className="flex flex-wrap items-end justify-between gap-4" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setMsg(null);
          try { const w = await setWipLimit(access, wip ? Number(wip) : null); onWip(w.wip_limit); setMsg({ ok: true, text: w.wip_limit ? `Limite de ${w.wip_limit} tarefas abertas por pessoa.` : "Sem limite de tarefas por pessoa." }); }
          catch (x) { setMsg({ ok: false, text: (x as Error).message }); }
          finally { setBusy(false); }
        }}>
          <div className="min-w-60 flex-1">
            <b>Tarefas abertas por pessoa</b>
            <p className="text-muted-foreground">Acima disto a pessoa aparece em sobrecarga na Carga. É um aviso: não impede atribuir.</p>
          </div>
          <span className="flex items-center gap-2">
            <Input type="number" min={1} max={100} className="w-24" disabled={!s.can.tasks || busy} value={wip} onChange={(e) => setWip(e.target.value)} placeholder="sem" aria-label="Limite de tarefas abertas por pessoa" />
            {s.can.tasks && <Button type="submit" size="sm" variant="outline" disabled={busy}>Guardar</Button>}
            {!s.can.tasks && s.wip_limit && <Badge variant="outline">{s.wip_limit}</Badge>}
          </span>
        </form>
      </CardContent>
    </Card>
  );
}
