/*
 * Olhar na câmara (PRD §46.1, GAZE-01/02, CHG-008). Funções puras, sem browser: testadas em tests/gaze.test.mts.
 *
 * GAZE-01: cada linha obriga o olho a varrer a coluna. Ângulo = 2·atan(largura / (2·distância)); o público só sente
 * contacto visual dentro de um cone estreito, por isso o alvo é ±3° (meio ângulo) e o teto ±4,5°.
 * GAZE-02: modo frase, 2 a 4 palavras por linha, com as quebras nas pausas naturais.
 */

export const GAZE_TARGET_DEG = 3;
export const GAZE_CEILING_DEG = 4.5;
export const DISTANCE_RANGE = { min: 0.3, max: 6 } as const;
export const SCREEN_RANGE = { min: 4, max: 100 } as const;

const rad = (deg: number) => (deg * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;

/** Largura máxima da coluna (cm) para que cada linha fique dentro de ±halfDeg à distância dada (m). 1 m → ≈10,5 cm. */
export function columnWidthCm(distanceM: number, halfDeg = GAZE_TARGET_DEG): number {
  if (!(distanceM > 0) || !(halfDeg > 0) || halfDeg >= 90) return 0;
  return 2 * distanceM * 100 * Math.tan(rad(halfDeg));
}

/** Meio ângulo (graus) que uma linha com esta largura (cm) varre à distância dada (m). */
export function halfAngleDeg(widthCm: number, distanceM: number): number {
  if (!(widthCm > 0) || !(distanceM > 0)) return 0;
  return deg(Math.atan(widthCm / 100 / (2 * distanceM)));
}

/**
 * Píxeis CSS por centímetro no ecrã físico. A diagonal é a do ecrã inteiro (não da janela); a resolução vem em
 * píxeis do dispositivo (screen.width × devicePixelRatio), e um píxel CSS são `dpr` píxeis do dispositivo.
 */
export function cssPxPerCm(screen: { widthPx: number; heightPx: number; dpr: number; diagonalIn: number }): number {
  const { widthPx, heightPx, dpr, diagonalIn } = screen;
  if (!(widthPx > 0) || !(heightPx > 0) || !(dpr > 0) || !(diagonalIn > 0)) return 0;
  const devicePpi = Math.hypot(widthPx, heightPx) / diagonalIn;
  return devicePpi / dpr / 2.54;
}

export type GazeColumn = {
  /** largura a aplicar à coluna, em px CSS (null = não se sabe o tamanho do ecrã: fica a coluna antiga) */
  maxPx: number | null;
  /** largura pedida pelo alvo, em cm */
  targetCm: number;
  /** cabe menos do que o alvo (ecrã estreito): a coluna fica com a largura disponível */
  limitedByScreen: boolean;
  pxPerCm: number;
};

/** Coluna para o alvo de ±3°, limitada à largura disponível na janela. */
export function gazeColumn(o: {
  distanceM: number; diagonalIn: number | null; screenWidthCss: number; screenHeightCss: number; dpr: number; availablePx: number;
}): GazeColumn {
  const targetCm = columnWidthCm(o.distanceM);
  if (!o.diagonalIn) return { maxPx: null, targetCm, limitedByScreen: false, pxPerCm: 0 };
  const pxPerCm = cssPxPerCm({ widthPx: o.screenWidthCss * o.dpr, heightPx: o.screenHeightCss * o.dpr, dpr: o.dpr, diagonalIn: o.diagonalIn });
  if (!pxPerCm) return { maxPx: null, targetCm, limitedByScreen: false, pxPerCm: 0 };
  const want = targetCm * pxPerCm;
  const avail = Math.max(0, o.availablePx);
  return { maxPx: Math.max(1, Math.floor(Math.min(want, avail || want))), targetCm, limitedByScreen: avail > 0 && want > avail, pxPerCm };
}

export type GazeLevel = "ok" | "acima_alvo" | "acima_teto";
/** ok até ±3° (com folga de arredondamento), acima do alvo até ±4,5°, acima do teto depois. */
export function gazeLevel(halfDeg: number): GazeLevel {
  if (halfDeg > GAZE_CEILING_DEG + 0.05) return "acima_teto";
  if (halfDeg > GAZE_TARGET_DEG + 0.05) return "acima_alvo";
  return "ok";
}

/** "±3,0°" em PT-PT. */
export const fmtDeg = (d: number) => `±${d.toLocaleString("pt-PT", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}°`;
export const fmtCm = (cm: number) => `${cm.toLocaleString("pt-PT", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} cm`;

// ---------- modo frase (GAZE-02) ----------

/** Palavras antes das quais se quebra de boa vontade (conjunções e relativos do PT-PT falado). */
const BREAK_BEFORE = new Set([
  "e", "mas", "ou", "nem", "porque", "pois", "que", "quando", "se", "como", "porém", "contudo", "todavia", "embora",
  "enquanto", "onde", "então", "logo", "portanto", "senão", "caso", "assim", "depois", "antes", "até", "sem", "para",
]);
/** Palavras curtas que não devem ficar a fechar uma linha (artigos, preposições, contrações). */
const NO_END = new Set([
  "a", "o", "as", "os", "um", "uma", "uns", "umas", "de", "do", "da", "dos", "das", "em", "no", "na", "nos", "nas",
  "ao", "aos", "à", "às", "por", "pelo", "pela", "pelos", "pelas", "com", "num", "numa", "dum", "duma", "e", "ou",
  "que", "se", "me", "te", "lhe", "não", "mais", "muito", "meu", "minha", "teu", "tua", "seu", "sua", "este", "esta", "esse", "essa",
]);

const hasWordChar = (t: string) => /[\p{L}\p{N}]/u.test(t);
const bare = (t: string) => t.toLocaleLowerCase("pt-PT").replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
const STRONG_END = /[.!?;:…]["»”')\]]*$/u;
const SOFT_END = /[,—–]["»”')\]]*$/u;

/**
 * Parte um parágrafo em linhas de 2 a 4 palavras (1 só se o parágrafo tiver uma palavra), com as quebras nas pausas:
 * fim de frase, vírgula, antes de conjunções; evita fechar a linha num artigo ou preposição.
 * Pontuação solta (— ou …) fica colada à palavra anterior e não conta como palavra.
 */
export function phraseLines(paragraph: string, min = 2, max = 4): string[] {
  const raw = paragraph.split(/\s+/).filter(Boolean);
  const words: string[] = [];
  for (const t of raw) {
    if (!hasWordChar(t) && words.length) words[words.length - 1] += ` ${t}`;
    else words.push(t);
  }
  // pontuação solta no início (sem palavra antes) junta-se à palavra seguinte
  while (words.length > 1 && !hasWordChar(words[0])) { words[1] = `${words[0]} ${words[1]}`; words.shift(); }
  const n = words.length;
  if (n === 0) return [];
  if (n < 2 * min && n <= max) return [words.join(" ")];

  // custo de quebrar depois da palavra i (0-based) — quanto menor, melhor
  const breakCost = (i: number) => {
    const w = words[i], next = words[i + 1];
    if (STRONG_END.test(w)) return 0;
    if (SOFT_END.test(w)) return 1;
    let c = 4;
    if (next && BREAK_BEFORE.has(bare(next))) c = 2;
    if (NO_END.has(bare(w))) c += 4;
    return c;
  };
  // custo de uma pausa forte que fica a meio da linha (o olho tem de parar a meio)
  const insideCost = (from: number, to: number) => {
    let c = 0;
    for (let i = from; i < to - 1; i++) c += STRONG_END.test(words[i]) ? 6 : SOFT_END.test(words[i]) ? 2 : 0;
    return c;
  };
  const sizeCost = (k: number) => (k === 3 ? 0 : k === 2 ? 0.6 : 0.4);

  const best = new Array<number>(n + 1).fill(Infinity);
  const prev = new Array<number>(n + 1).fill(-1);
  best[0] = 0;
  for (let j = 1; j <= n; j++) {
    for (let k = min; k <= max; k++) {
      const i = j - k;
      if (i < 0 || best[i] === Infinity) continue;
      const c = best[i] + sizeCost(k) + insideCost(i, j) + (j < n ? breakCost(j - 1) : 0);
      if (c < best[j]) { best[j] = c; prev[j] = i; }
    }
  }
  if (best[n] === Infinity) return [words.join(" ")];
  const out: string[] = [];
  for (let j = n; j > 0; j = prev[j]) out.unshift(words.slice(prev[j], j).join(" "));
  return out;
}

/** Número de palavras de uma linha (o que o teste E2E confirma). */
export const wordCount = (line: string) => line.split(/\s+/).filter(hasWordChar).length;

/** Texto de um bloco (parágrafos separados por linha) em parágrafos de linhas curtas. */
export function phraseParagraphs(text: string): string[][] {
  return text.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => phraseLines(l));
}
