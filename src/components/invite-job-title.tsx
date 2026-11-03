"use client";

import { useEffect, useState } from "react";
import { fetchJobTemplates, type JobTemplate } from "@/lib/learn";

const selectCls = "h-9 rounded-md border bg-background px-2 text-sm";

export type JobPick = { key: string; grants: string[] } | null;

/**
 * Cargo no convite (BIZ-08, flag team.job_titles): o cargo sugere o papel e exceções típicas, ajustáveis antes de
 * convidar. O cargo não dá permissões sozinho: o que dá acesso é o papel e cada exceção marcada (AGENTS §2.4).
 */
export function JobTitlePicker({ ws, roles, value, onChange, onRole }: {
  ws: string; roles: readonly string[]; value: JobPick; onChange: (v: JobPick) => void; onRole: (role: string) => void;
}) {
  const [data, setData] = useState<{ can_grant: boolean; templates: JobTemplate[] } | null>(null);
  const [err, setErr] = useState("");
  useEffect(() => {
    let alive = true;
    fetchJobTemplates(ws).then((d) => { if (alive) setData(d); }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [ws]);
  if (err) return <p className="text-xs text-muted-foreground" role="status">Cargos indisponíveis agora ({err}). Podes convidar só com o papel.</p>;
  if (!data) return <p className="text-xs text-muted-foreground" aria-busy="true">A carregar cargos…</p>;
  const t = data.templates.find((x) => x.key === value?.key) ?? null;
  return (
    <div className="flex flex-col gap-2 rounded-md border p-3" data-job-title>
      <label className="flex flex-col gap-1.5 text-sm font-medium">Cargo
        <select className={selectCls} value={value?.key ?? ""} onChange={(e) => {
          const nt = data.templates.find((x) => x.key === e.target.value);
          if (!nt) { onChange(null); return; }
          if (roles.includes(nt.role)) onRole(nt.role);
          onChange({ key: nt.key, grants: nt.grant_options.filter((g) => g.grantable && !g.in_role).map((g) => g.key) });
        }}>
          <option value="">Sem cargo</option>
          {data.templates.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}
        </select>
      </label>
      {t && (
        <div className="flex flex-col gap-1 text-sm">
          <p className="text-xs text-muted-foreground">
            Sugere o papel {t.role}{roles.includes(t.role) ? "" : " (acima do teu: escolhe outro papel)"}. Módulos típicos: {t.modules}.{t.note ? ` ${t.note}` : ""} O cargo não dá permissões por si.
          </p>
          {t.grant_options.length === 0 && <p className="text-xs text-muted-foreground">O papel já cobre o que este cargo costuma precisar.</p>}
          {t.grant_options.length > 0 && (
            <fieldset className="flex flex-col gap-1">
              <legend className="text-xs font-medium">Exceções sugeridas (podes tirar)</legend>
              {t.grant_options.map((g) => (
                <label key={g.key} className="flex items-center gap-2 text-sm">
                  <input type="checkbox" disabled={!g.grantable || g.in_role} checked={!g.in_role && !!value?.grants.includes(g.key)}
                    onChange={(e) => onChange({ key: t.key, grants: e.target.checked ? [...(value?.grants ?? []), g.key] : (value?.grants ?? []).filter((x) => x !== g.key) })} />
                  {g.label}
                  {g.in_role && <span className="text-xs text-muted-foreground">(já no papel)</span>}
                  {!g.in_role && !g.grantable && <span className="text-xs text-muted-foreground">({data.can_grant ? "não a tens para dar" : "precisa de Gerir permissões"})</span>}
                </label>
              ))}
            </fieldset>
          )}
        </div>
      )}
    </div>
  );
}
