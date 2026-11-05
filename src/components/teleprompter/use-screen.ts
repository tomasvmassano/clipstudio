"use client";

import { useSyncExternalStore } from "react";

/** Ecrã físico em px CSS e devicePixelRatio (GAZE-01). Muda ao rodar o iPad, mudar de monitor ou ampliar. */
export type ScreenInfo = { width: number; height: number; dpr: number };

const subscribe = (cb: () => void) => {
  window.addEventListener("resize", cb);
  window.addEventListener("orientationchange", cb);
  return () => { window.removeEventListener("resize", cb); window.removeEventListener("orientationchange", cb); };
};
// uma string estável: o useSyncExternalStore compara por valor
const snap = () => `${window.screen.width}x${window.screen.height}@${window.devicePixelRatio || 1}`;

export function useScreenInfo(): ScreenInfo | null {
  const s = useSyncExternalStore(subscribe, snap, () => "");
  if (!s) return null;
  const m = /^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)@(\d+(?:\.\d+)?)$/.exec(s);
  return m ? { width: +m[1], height: +m[2], dpr: +m[3] } : null;
}

/** "4:3", "16:10"... para mostrar a forma do ecrã detetada. */
export function aspectLabel(w: number, h: number): string {
  const a = Math.max(w, h), b = Math.min(w, h);
  const known: [number, number][] = [[4, 3], [3, 2], [16, 10], [16, 9], [19.5, 9], [21, 9]];
  const r = a / b;
  const best = known.reduce((x, y) => (Math.abs(y[0] / y[1] - r) < Math.abs(x[0] / x[1] - r) ? y : x));
  return Math.abs(best[0] / best[1] - r) < 0.03 ? `${best[0]}:${best[1]}`.replace(".", ",") : r.toFixed(2).replace(".", ",") + ":1";
}
