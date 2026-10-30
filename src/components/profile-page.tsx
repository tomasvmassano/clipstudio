"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useTheme } from "next-themes";
import { CheckIcon, KeyRoundIcon, Loader2Icon, LogOutIcon, ShieldCheckIcon, UploadIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import { MyDataCard } from "@/components/my-data-card";
import { MyNotifCard } from "@/components/notif/my-notif-card";
import { supabase } from "@/lib/supabase";
import { avatarUrl, AVATAR_MAX, AVATAR_TYPES, SECURITY_LABEL, securityEvent, securityLog, updateProfile, uploadAvatar } from "@/lib/profile";

const selectCls = "h-9 rounded-md border bg-background px-2 text-sm";
const initials = (s: string) => s.split(/[\s@.]+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase()).join("") || "?";
const fmt = (d: string) => new Date(d).toLocaleString("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

type Note = { ok: boolean; text: string } | null;
function NoteLine({ note }: { note: Note }) {
  if (!note) return null;
  return <p className={`text-sm ${note.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"}`} role={note.ok ? "status" : "alert"}>{note.text}</p>;
}

/** /perfil (W1-15): identidade, palavra-passe, verificação em dois passos, preferências e segurança da própria pessoa. */
export function ProfilePage() {
  const { mode, profile, workspaces } = useSession();
  if (mode === "loading") return <div className="flex flex-col gap-4"><Skeleton className="h-8 w-40" /><Skeleton className="h-48" /><Skeleton className="h-48" /></div>;
  if (mode !== "user" || !profile) {
    return (
      <Alert><AlertDescription>O perfil é de quem entra com conta própria. Com o código de equipa não há perfil: pede um convite para teres a tua conta.</AlertDescription></Alert>
    );
  }
  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Perfil</h1>
        <p className="text-sm text-muted-foreground">Só tu vês e mudas isto. As permissões em cada cliente são geridas por quem gere a equipa.</p>
      </div>
      <Identity />
      <Password />
      <Mfa />
      <Preferences workspaces={workspaces.map((w) => ({ id: w.id, name: w.name }))} />
      <MyNotifCard />
      <Security />
      <MyDataCard />
    </div>
  );
}

function Identity() {
  const { profile, refresh } = useSession();
  const [name, setName] = useState(profile?.display_name ?? "");
  const [url, setUrl] = useState<string | null>(null);
  const [busy, setBusy] = useState<"" | "name" | "avatar">("");
  const [note, setNote] = useState<Note>(null);
  useEffect(() => { let alive = true; avatarUrl(profile?.avatar_path).then((u) => { if (alive) setUrl(u); }); return () => { alive = false; }; }, [profile?.avatar_path]);
  if (!profile) return null;
  return (
    <Card>
      <CardHeader><CardTitle>Identidade</CardTitle><CardDescription>O nome aparece no menu e no que fazes na app.</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex items-center gap-4">
          <Avatar className="size-16">
            {url && <AvatarImage src={url} alt="" />}
            <AvatarFallback>{initials(profile.display_name || profile.email)}</AvatarFallback>
          </Avatar>
          <label className="inline-flex">
            <input
              type="file" accept={AVATAR_TYPES.join(",")} className="sr-only" disabled={!!busy}
              onChange={async (e) => {
                const f = e.target.files?.[0]; e.target.value = "";
                if (!f) return;
                if (f.size > AVATAR_MAX) { setNote({ ok: false, text: "A imagem tem de ter até 1 MB." }); return; }
                setBusy("avatar"); setNote(null);
                try { await uploadAvatar(profile.id, f); await refresh(); setNote({ ok: true, text: "Fotografia guardada." }); }
                catch (err) { setNote({ ok: false, text: (err as Error).message }); }
                finally { setBusy(""); }
              }}
            />
            <span className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md border px-3 text-sm hover:bg-accent">
              {busy === "avatar" ? <Loader2Icon className="size-4 animate-spin" /> : <UploadIcon className="size-4" />} Mudar fotografia
            </span>
          </label>
          {profile.avatar_path && (
            <Button variant="ghost" size="sm" disabled={!!busy} onClick={async () => {
              setBusy("avatar"); setNote(null);
              try { await updateProfile({ avatar_path: null }); await refresh(); } catch (err) { setNote({ ok: false, text: (err as Error).message }); } finally { setBusy(""); }
            }}>Tirar</Button>
          )}
        </div>
        <form className="flex flex-col gap-2 sm:flex-row sm:items-end" onSubmit={async (e) => {
          e.preventDefault(); setBusy("name"); setNote(null);
          try { await updateProfile({ display_name: name.trim() || null }); await refresh(); setNote({ ok: true, text: "Nome guardado." }); }
          catch (err) { setNote({ ok: false, text: (err as Error).message }); }
          finally { setBusy(""); }
        }}>
          <label className="flex flex-1 flex-col gap-1 text-sm font-medium" htmlFor="pf-name">Nome
            <Input id="pf-name" maxLength={80} value={name} onChange={(e) => setName(e.target.value)} placeholder="Como te chamam" />
          </label>
          <Button type="submit" disabled={busy === "name" || (name.trim() || null) === (profile.display_name ?? null)}>
            {busy === "name" && <Loader2Icon className="animate-spin" />} Guardar
          </Button>
        </form>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">Email</span><b>{profile.email}</b>
          {profile.confirmed ? <Badge variant="secondary"><CheckIcon /> verificado</Badge> : <Badge variant="destructive">por confirmar</Badge>}
        </div>
        <NoteLine note={note} />
      </CardContent>
    </Card>
  );
}

function Password() {
  const { profile } = useSession();
  const params = useSearchParams();
  const recovering = params.get("recuperar") === "1";
  const [cur, setCur] = useState(""); const [p1, setP1] = useState(""); const [p2, setP2] = useState("");
  const [busy, setBusy] = useState(false); const [note, setNote] = useState<Note>(null);
  if (!profile) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Palavra-passe</CardTitle>
        <CardDescription>{recovering ? "Entraste pelo link de recuperação. Escolhe a palavra-passe nova." : "Para mudar, confirma primeiro a atual."}</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setNote(null);
          if (p1.length < 8) { setNote({ ok: false, text: "A palavra-passe tem de ter pelo menos 8 caracteres." }); return; }
          if (p1 !== p2) { setNote({ ok: false, text: "As duas palavras-passe novas não são iguais." }); return; }
          setBusy(true);
          try {
            const sb = supabase();
            if (!recovering) {
              const { error } = await sb.auth.signInWithPassword({ email: profile.email, password: cur });
              if (error) throw new Error("A palavra-passe atual não está certa.");
            }
            const { error } = await sb.auth.updateUser({ password: p1 });
            if (error) throw new Error(error.message.toLowerCase().includes("different") ? "A nova tem de ser diferente da atual." : "Não foi possível mudar a palavra-passe. Tenta outra vez.");
            await securityEvent("security.password_changed");
            setCur(""); setP1(""); setP2("");
            setNote({ ok: true, text: "Palavra-passe mudada. As outras sessões continuam abertas: termina-as em Segurança se precisares." });
          } catch (err) { setNote({ ok: false, text: (err as Error).message }); }
          finally { setBusy(false); }
        }}>
          {!recovering && (
            <label className="flex flex-col gap-1 text-sm font-medium" htmlFor="pf-cur">Palavra-passe atual
              <Input id="pf-cur" type="password" autoComplete="current-password" required value={cur} onChange={(e) => setCur(e.target.value)} />
            </label>
          )}
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="flex flex-col gap-1 text-sm font-medium" htmlFor="pf-new">Nova (mínimo 8)
              <Input id="pf-new" type="password" autoComplete="new-password" required minLength={8} value={p1} onChange={(e) => setP1(e.target.value)} />
            </label>
            <label className="flex flex-col gap-1 text-sm font-medium" htmlFor="pf-new2">Repetir a nova
              <Input id="pf-new2" type="password" autoComplete="new-password" required value={p2} onChange={(e) => setP2(e.target.value)} />
            </label>
          </div>
          <div><Button type="submit" disabled={busy}>{busy ? <Loader2Icon className="animate-spin" /> : <KeyRoundIcon />} Mudar palavra-passe</Button></div>
          <NoteLine note={note} />
        </form>
      </CardContent>
    </Card>
  );
}

type Factor = { id: string; status: string; friendly_name?: string | null; created_at?: string };

function Mfa() {
  const [factors, setFactors] = useState<Factor[] | null>(null);
  const [enroll, setEnroll] = useState<{ id: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<Note>(null);
  const [unavailable, setUnavailable] = useState(false);

  const load = useCallback(async () => {
    const { data, error } = await supabase().auth.mfa.listFactors();
    if (error) { setUnavailable(true); setFactors([]); return; }
    setFactors((data?.totp ?? []) as Factor[]);
  }, []);
  useEffect(() => { queueMicrotask(() => void load()); }, [load]);

  const verified = factors?.find((f) => f.status === "verified");
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">Verificação em dois passos {verified && <Badge variant="secondary"><ShieldCheckIcon /> ligada</Badge>}</CardTitle>
        <CardDescription>Além da palavra-passe, pede um código da app de autenticação (Google Authenticator, 1Password, Authy) sempre que entras.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {factors === null && <Skeleton className="h-9 w-48" />}
        {unavailable && <p className="text-sm text-muted-foreground">A verificação em dois passos não está disponível neste momento.</p>}
        {factors && !unavailable && !verified && !enroll && (
          <div><Button disabled={busy} onClick={async () => {
            setBusy(true); setNote(null);
            const sb = supabase();
            // limpa tentativas anteriores que ficaram por verificar
            for (const f of factors.filter((x) => x.status !== "verified")) await sb.auth.mfa.unenroll({ factorId: f.id }).catch(() => undefined);
            const { data, error } = await sb.auth.mfa.enroll({ factorType: "totp", friendlyName: `ClipStudio ${new Date().toISOString().slice(0, 10)}` });
            setBusy(false);
            if (error || !data) { setNote({ ok: false, text: error?.message.toLowerCase().includes("disabled") ? "A verificação em dois passos não está ligada neste projeto." : "Não foi possível começar. Tenta outra vez." }); return; }
            setEnroll({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
          }}>{busy ? <Loader2Icon className="animate-spin" /> : <ShieldCheckIcon />} Ligar</Button></div>
        )}
        {enroll && (
          <form className="flex flex-col gap-3" onSubmit={async (e) => {
            e.preventDefault(); setBusy(true); setNote(null);
            const { error } = await supabase().auth.mfa.challengeAndVerify({ factorId: enroll.id, code: code.replace(/\s/g, "") });
            setBusy(false);
            if (error) { setNote({ ok: false, text: "Código errado ou expirado. Usa o código que está agora na app." }); return; }
            await securityEvent("security.mfa_enabled");
            setEnroll(null); setCode(""); setNote({ ok: true, text: "Ligada. Da próxima vez que entrares pedimos o código." });
            void load();
          }}>
            <p className="text-sm">1. Lê este código QR com a app de autenticação. Se não conseguires, escreve a chave à mão.</p>
            {/* eslint-disable-next-line @next/next/no-img-element -- QR em data URI devolvido pelo Supabase Auth */}
            <img src={enroll.qr} alt="Código QR da verificação em dois passos" className="size-44 rounded-md bg-white p-2" />
            <code className="w-fit rounded bg-muted px-2 py-1 text-xs break-all">{enroll.secret}</code>
            <label className="flex max-w-xs flex-col gap-1 text-sm font-medium" htmlFor="mfa-code">2. Escreve o código de 6 dígitos que a app mostra
              <Input id="mfa-code" inputMode="numeric" autoComplete="one-time-code" maxLength={8} value={code} onChange={(e) => setCode(e.target.value)} />
            </label>
            <div className="flex gap-2">
              <Button type="submit" disabled={busy || code.replace(/\s/g, "").length < 6}>{busy && <Loader2Icon className="animate-spin" />} Confirmar</Button>
              <Button type="button" variant="ghost" disabled={busy} onClick={async () => { await supabase().auth.mfa.unenroll({ factorId: enroll.id }).catch(() => undefined); setEnroll(null); setCode(""); }}>Cancelar</Button>
            </div>
          </form>
        )}
        {verified && (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-muted-foreground">App ligada {verified.created_at ? `a ${fmt(verified.created_at)}` : ""}</span>
            <Button variant="outline" size="sm" disabled={busy} onClick={async () => {
              setBusy(true); setNote(null);
              const { error } = await supabase().auth.mfa.unenroll({ factorId: verified.id });
              setBusy(false);
              if (error) { setNote({ ok: false, text: "Para desligar, entra outra vez com o código da app." }); return; }
              await securityEvent("security.mfa_disabled");
              setNote({ ok: true, text: "Desligada. Passas a entrar só com a palavra-passe." });
              await supabase().auth.refreshSession().catch(() => undefined);
              void load();
            }}>Desligar</Button>
          </div>
        )}
        <NoteLine note={note} />
      </CardContent>
    </Card>
  );
}

function Preferences({ workspaces }: { workspaces: { id: string; name: string }[] }) {
  const { profile, refresh } = useSession();
  const { setTheme } = useTheme();
  const zones = useMemo(() => {
    try { return (Intl as unknown as { supportedValuesOf: (k: string) => string[] }).supportedValuesOf("timeZone"); } catch { return ["Asia/Dubai", "Europe/Lisbon", "UTC"]; }
  }, []);
  const [busy, setBusy] = useState(false); const [note, setNote] = useState<Note>(null);
  if (!profile) return null;
  const save = async (patch: Parameters<typeof updateProfile>[0], ok: string) => {
    setBusy(true); setNote(null);
    try { await updateProfile(patch); await refresh(); setNote({ ok: true, text: ok }); }
    catch (err) { setNote({ ok: false, text: (err as Error).message }); }
    finally { setBusy(false); }
  };
  return (
    <Card>
      <CardHeader><CardTitle>Preferências</CardTitle><CardDescription>Idioma: português de Portugal. As datas de cada cliente seguem o fuso do cliente; o teu fuso é para o que é só teu.</CardDescription></CardHeader>
      <CardContent className="grid gap-4 sm:grid-cols-3">
        <label className="flex flex-col gap-1 text-sm font-medium">O teu fuso
          <select aria-label="O teu fuso" className={selectCls} disabled={busy} value={profile.timezone ?? ""}
            onChange={(e) => void save({ timezone: e.target.value || null }, "Fuso guardado.")}>
            <option value="">Do browser ({Intl.DateTimeFormat().resolvedOptions().timeZone})</option>
            {zones.map((z) => <option key={z} value={z}>{z}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm font-medium">Tema
          <select aria-label="Tema" className={selectCls} disabled={busy} value={profile.theme ?? "dark"}
            onChange={(e) => { const t = e.target.value as "system" | "light" | "dark"; setTheme(t); void save({ theme: t }, "Tema guardado."); }}>
            <option value="dark">Escuro</option><option value="light">Claro</option><option value="system">Como o sistema</option>
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm font-medium">Cliente ao entrar
          <select aria-label="Cliente ao entrar" className={selectCls} disabled={busy || workspaces.length === 0} value={profile.preferred_workspace ?? ""}
            onChange={(e) => void save({ preferred_workspace: e.target.value || null }, "Cliente preferido guardado.")}>
            <option value="">O último que abri</option>
            {workspaces.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        </label>
        <div className="sm:col-span-3"><NoteLine note={note} /></div>
      </CardContent>
    </Card>
  );
}

function Security() {
  const { signOut } = useSession();
  const [log, setLog] = useState<{ at: string; action: string }[] | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    securityLog().then((l) => { if (alive) setLog(l); }).catch((e) => { if (alive) { setErr((e as Error).message); setLog([]); } });
    return () => { alive = false; };
  }, []);
  return (
    <Card>
      <CardHeader><CardTitle>Segurança</CardTitle><CardDescription>Se perdeste um telemóvel ou entraste num computador que não é teu, termina todas as sessões.</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div><Button variant="outline" disabled={busy} onClick={async () => {
          setBusy(true);
          await securityEvent("security.signed_out_everywhere");
          await supabase().auth.signOut({ scope: "global" }).catch(() => undefined);
          await signOut();
        }}>{busy ? <Loader2Icon className="animate-spin" /> : <LogOutIcon />} Terminar sessão em todos os dispositivos</Button></div>
        <div className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Histórico recente</span>
          {log === null && <Skeleton className="h-16" />}
          {err && <p className="text-destructive" role="alert">{err}</p>}
          {log && log.length === 0 && !err && <p className="text-muted-foreground">Ainda nada.</p>}
          {log?.map((l, i) => (
            <div key={i} className="flex justify-between gap-2 border-b py-1 last:border-0">
              <span>{SECURITY_LABEL[l.action] ?? l.action}</span><span className="text-muted-foreground">{fmt(l.at)}</span>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
