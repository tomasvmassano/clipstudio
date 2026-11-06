"use client";

import { useEffect, useState } from "react";
import { ACTION_LABEL, DEFAULT_KEYS, keyName, type TpAction, type TpPrefs } from "@/lib/recording";
import { cn } from "@/lib/utils";
import { aspectLabel, useScreenInfo } from "@/components/teleprompter/use-screen";
import { DISTANCE_RANGE, GAZE_TARGET_DEG, SCREEN_RANGE, fmtCm, fmtDeg, gazeColumn } from "@/lib/gaze";

type Props = {
  prefs: TpPrefs;
  update: (p: Partial<TpPrefs>) => void;
  keysFor: (a: TpAction) => string[];
  serverSync: boolean;
  syncError: string;
  onClose: () => void;
};

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex items-center justify-between gap-4 py-2 text-sm">
      <span className="text-neutral-300">{label}</span>
      <span className="flex items-center gap-2">{children}</span>
    </label>
  );
}

function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} onClick={() => onChange(!on)}
      className={cn("h-8 min-w-14 rounded-full border px-3 text-xs font-semibold", on ? "border-amber-400 bg-amber-400 text-black" : "border-neutral-600 text-neutral-300")}>
      {on ? "Sim" : "Não"}
    </button>
  );
}

/** Número em PT-PT (aceita vírgula). Guarda ao escrever um valor válido; ao sair do campo repõe o guardado. */
function NumField({ label, value, min, max, onCommit, placeholder, allowEmpty }: {
  label: string; value: number | null; min: number; max: number; onCommit: (v: number | null) => void; placeholder?: string; allowEmpty?: boolean;
}) {
  const shown = value == null ? "" : value.toLocaleString("pt-PT", { maximumFractionDigits: 2 });
  const [draft, setDraft] = useState<string | null>(null);
  const parse = (t: string) => { const v = Number(t.trim().replace(",", ".")); return t.trim() && Number.isFinite(v) ? v : null; };
  const d = draft ?? shown;
  const v = parse(d);
  const invalid = draft != null && (d.trim() ? v == null || v < min || v > max : !allowEmpty);
  return (
    <span className="flex flex-col items-end">
      <input type="text" inputMode="decimal" aria-label={label} aria-invalid={invalid} placeholder={placeholder} value={d}
        onChange={(e) => {
          const t = e.target.value; setDraft(t);
          const n = parse(t);
          if (n != null && n >= min && n <= max) onCommit(n);
          else if (!t.trim() && allowEmpty) onCommit(null);
        }}
        onBlur={() => setDraft(null)}
        className={cn("h-11 w-24 rounded-lg border bg-neutral-900 px-2 text-right text-sm", invalid ? "border-red-500" : "border-neutral-700")} />
      {invalid && <span className="mt-1 text-xs text-red-400">entre {min.toLocaleString("pt-PT")} e {max.toLocaleString("pt-PT")}</span>}
    </span>
  );
}

/** Definições do teleprompter (FR-03-03/04/05). Escuro de propósito: usa-se no estúdio. */
export function TpSettings({ prefs, update, keysFor, serverSync, syncError, onClose }: Props) {
  const [capture, setCapture] = useState<TpAction | null>(null);
  const screen = useScreenInfo();
  const col = screen ? gazeColumn({ distanceM: prefs.distance_m, diagonalIn: prefs.screen_in, screenWidthCss: screen.width, screenHeightCss: screen.height, dpr: screen.dpr, availablePx: 0 }) : null;

  useEffect(() => {
    if (!capture) return;
    const onKey = (e: KeyboardEvent) => {
      e.preventDefault(); e.stopPropagation();
      if (e.key === "Escape" && capture !== "exit") { setCapture(null); return; }
      update({ keys: { ...prefs.keys, [capture]: [e.key] } });
      setCapture(null);
    };
    window.addEventListener("keydown", onKey, { capture: true });
    return () => window.removeEventListener("keydown", onKey, { capture: true });
  }, [capture, prefs.keys, update]);

  return (
    <div role="dialog" aria-label="Definições do teleprompter" className="fixed inset-y-0 right-0 z-[60] flex w-[min(100vw,26rem)] flex-col border-l border-neutral-800 bg-neutral-950 text-white shadow-2xl">
      <div className="flex items-center justify-between border-b border-neutral-800 px-4 py-3">
        <h2 className="text-base font-semibold">Definições</h2>
        <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-neutral-700 px-4 text-sm">Fechar</button>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-2">
        <p className="pb-2 text-xs text-neutral-500">
          {serverSync ? "Guardadas na tua conta para este dispositivo." : "Guardadas só neste dispositivo (código de equipa)."}
          {syncError && <span className="block text-red-400">Não consegui guardar na conta: {syncError}. Ficam neste dispositivo.</span>}
        </p>
        <Row label={`Velocidade (${prefs.speed})`}>
          <input type="range" min={1} max={10} value={prefs.speed} onChange={(e) => update({ speed: +e.target.value })} className="w-40 accent-amber-400" />
        </Row>
        <Row label={`Letra (${prefs.font} px)`}>
          <input type="range" min={32} max={96} step={2} value={prefs.font} onChange={(e) => update({ font: +e.target.value })} className="w-40 accent-amber-400" />
        </Row>
        <Row label={`Entrelinha (${prefs.line_height.toFixed(2)})`}>
          <input type="range" min={1} max={2.2} step={0.02} value={prefs.line_height} onChange={(e) => update({ line_height: +e.target.value })} className="w-40 accent-amber-400" />
        </Row>
        <Row label={`Margens (${prefs.margin}%)`}>
          <input type="range" min={0} max={25} value={prefs.margin} onChange={(e) => update({ margin: +e.target.value })} className="w-40 accent-amber-400" />
        </Row>
        <Row label="Espelho horizontal"><Toggle label="Espelho horizontal" on={prefs.mirror_h} onChange={(v) => update({ mirror_h: v })} /></Row>
        <Row label="Espelho vertical"><Toggle label="Espelho vertical" on={prefs.mirror_v} onChange={(v) => update({ mirror_v: v })} /></Row>
        <Row label="Contraste">
          <select value={prefs.contrast} onChange={(e) => update({ contrast: e.target.value as TpPrefs["contrast"] })}
            className="h-9 rounded-lg border border-neutral-700 bg-neutral-900 px-2 text-sm">
            <option value="normal">Branco</option>
            <option value="alto">Alto contraste</option>
            <option value="ambar">Âmbar</option>
          </select>
        </Row>

        <h3 className="mt-4 border-t border-neutral-800 pt-3 text-sm font-semibold">Olhar na câmara</h3>
        <p className="pb-1 text-xs text-neutral-500">
          Quanto mais larga a linha, mais os olhos varrem e mais se nota que estás a ler. A coluna fica com a largura que cabe em {fmtDeg(GAZE_TARGET_DEG)} à distância a que lês. Guardado só para este dispositivo.
        </p>
        <Row label="Distância à câmara (m)">
          <NumField label="Distância à câmara em metros" value={prefs.distance_m} min={DISTANCE_RANGE.min} max={DISTANCE_RANGE.max} onCommit={(v) => v != null && update({ distance_m: v })} />
        </Row>
        <Row label="Tamanho do ecrã (polegadas, diagonal)">
          <NumField label="Tamanho do ecrã em polegadas" value={prefs.screen_in} min={SCREEN_RANGE.min} max={SCREEN_RANGE.max} placeholder="ex.: 12,9" allowEmpty onCommit={(v) => update({ screen_in: v })} />
        </Row>
        <Row label="Coluna pela distância"><Toggle label="Coluna pela distância" on={prefs.column_fit} onChange={(v) => update({ column_fit: v })} /></Row>
        <p data-gaze-target className="pb-2 text-xs text-neutral-400">
          {col ? <>Alvo {fmtDeg(GAZE_TARGET_DEG)}: coluna de {fmtCm(col.targetCm)} a {prefs.distance_m.toLocaleString("pt-PT")} m</> : null}
          {col?.pxPerCm ? <> ({Math.round(col.targetCm * col.pxPerCm)} px neste ecrã de {screen!.width}×{screen!.height}, {aspectLabel(screen!.width, screen!.height)}). Mede a coluna com uma régua: se não der {fmtCm(col.targetCm)}, corrige a diagonal.</>
            : <>. Indica a diagonal do ecrã para a app saber quantos píxeis tem cada centímetro{screen ? ` (ecrã detetado: ${screen.width}×${screen.height}, ${aspectLabel(screen.width, screen.height)})` : ""}.</>}
          {!prefs.column_fit && <span className="block text-amber-400">Desligado: a coluna volta a ter até 1100 px e o ângulo aparece no topo.</span>}
        </p>
        <Row label={`Linha de foco (${prefs.focus_pct}% do topo)`}>
          <input type="range" min={5} max={60} value={prefs.focus_pct} aria-label="Altura da linha de foco" onChange={(e) => update({ focus_pct: +e.target.value })} className="w-40 accent-amber-400" />
        </Row>
        <p className="pb-1 text-xs text-neutral-500">Põe a linha à altura da lente: é aí que o texto que estás a dizer fica parado.</p>
        <Row label="Modo frase (2 a 4 palavras por linha)"><Toggle label="Modo frase" on={prefs.phrase_mode} onChange={(v) => update({ phrase_mode: v })} /></Row>

        <Row label="Perguntar se gravaste ao passar ao seguinte"><Toggle label="Perguntar se gravaste" on={prefs.confirm_on_advance} onChange={(v) => update({ confirm_on_advance: v })} /></Row>

        <h3 className="mt-4 border-t border-neutral-800 pt-3 text-sm font-semibold">Atalhos e comando</h3>
        <p className="pb-2 text-xs text-neutral-500">Os comandos Bluetooth de teleprompter funcionam como teclado (setas, PageUp/PageDown, Espaço, Enter). Carrega em Mudar e depois no botão do comando.</p>
        {(Object.keys(DEFAULT_KEYS) as TpAction[]).map((a) => (
          <div key={a} className="flex items-center justify-between gap-3 py-1.5 text-sm">
            <span className="text-neutral-300">{ACTION_LABEL[a]}</span>
            <span className="flex items-center gap-2">
              <kbd className="min-w-16 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-center text-xs">
                {capture === a ? "carrega…" : keysFor(a).map(keyName).join(" · ")}
              </kbd>
              <button type="button" onClick={() => setCapture(a)} className="min-h-9 rounded-md border border-neutral-700 px-2 text-xs">Mudar</button>
            </span>
          </div>
        ))}
        <button type="button" onClick={() => update({ keys: {} })} className="mt-2 min-h-10 rounded-lg border border-neutral-700 px-3 text-sm">Repor atalhos</button>
      </div>
    </div>
  );
}
