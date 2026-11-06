import {
  columnWidthCm, halfAngleDeg, cssPxPerCm, gazeColumn, gazeLevel, fmtDeg, phraseLines, phraseParagraphs, wordCount,
} from "../src/lib/gaze.ts";

const near = (a: number, b: number, eps = 0.05) => Math.abs(a - b) <= eps;
const allSizes = (lines: string[]) => lines.every((l) => { const n = wordCount(l); return n >= 2 && n <= 4; });

const hook = "Sabias que o homem mais rico de Portugal acorda às cinco da manhã, todos os dias, sem despertador?";
const body = "Isto não é sorte. É método e disciplina, porque quem trabalha cedo ganha tempo para pensar — e pensar é o que paga.";
const cta = "Segue para mais.";
const longWord = "Portugal";

const cases: [string, unknown, unknown][] = [
  // GAZE-01: geometria (PRD §46.1: ≈10,5 cm a 1 m, ≈26 cm a 2,5 m)
  ["1 m → ≈10,5 cm", near(columnWidthCm(1), 10.48), true],
  ["2,5 m → ≈26 cm", near(columnWidthCm(2.5), 26.2), true],
  ["teto ±4,5° a 1 m → ≈15,7 cm", near(columnWidthCm(1, 4.5), 15.74), true],
  ["ida e volta: largura do alvo dá ±3°", near(halfAngleDeg(columnWidthCm(1.7), 1.7), 3, 1e-9), true],
  ["coluna antiga de 1100 px num portátil a 1 m passa o teto", gazeLevel(halfAngleDeg(1100 / cssPxPerCm({ widthPx: 2880, heightPx: 1800, dpr: 2, diagonalIn: 15.4 }) , 1)), "acima_teto"],
  ["distância inválida", columnWidthCm(0), 0],
  ["ângulo com distância inválida", halfAngleDeg(10, 0), 0],
  // px CSS por cm: iPad 10,2" (2160×1620 px, dpr 2) → 1080×810 CSS px; diagonal 1350 CSS px / 25,9 cm ≈ 52,1
  ["iPad 10,2\": px CSS/cm", near(cssPxPerCm({ widthPx: 2160, heightPx: 1620, dpr: 2, diagonalIn: 10.2 }), 52.11, 0.05), true],
  ["dpr não muda o tamanho físico", near(
    cssPxPerCm({ widthPx: 2160, heightPx: 1620, dpr: 2, diagonalIn: 10.2 }),
    cssPxPerCm({ widthPx: 1080, heightPx: 810, dpr: 1, diagonalIn: 10.2 }), 1e-9), true],
  ["orientação não muda", cssPxPerCm({ widthPx: 1620, heightPx: 2160, dpr: 2, diagonalIn: 10.2 }) === cssPxPerCm({ widthPx: 2160, heightPx: 1620, dpr: 2, diagonalIn: 10.2 }), true],
  ["sem diagonal", cssPxPerCm({ widthPx: 1, heightPx: 1, dpr: 1, diagonalIn: 0 }), 0],
  ["coluna sem tamanho do ecrã fica a antiga", gazeColumn({ distanceM: 1, diagonalIn: null, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 900 }).maxPx, null],
  ["coluna no iPad a 1 m ≈ 546 px", gazeColumn({ distanceM: 1, diagonalIn: 10.2, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 900 }).maxPx, 546],
  ["mais longe, coluna mais larga", gazeColumn({ distanceM: 1.5, diagonalIn: 10.2, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 2000 }).maxPx! >
    gazeColumn({ distanceM: 1, diagonalIn: 10.2, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 2000 }).maxPx!, true],
  ["limitada pelo ecrã a 2,5 m", gazeColumn({ distanceM: 2.5, diagonalIn: 10.2, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 900 }).limitedByScreen, true],
  ["limitada: usa a largura disponível", gazeColumn({ distanceM: 2.5, diagonalIn: 10.2, screenWidthCss: 1080, screenHeightCss: 810, dpr: 2, availablePx: 900 }).maxPx, 900],
  ["nível ok a 3°", gazeLevel(3), "ok"],
  ["nível acima do alvo", gazeLevel(4), "acima_alvo"],
  ["nível acima do teto", gazeLevel(4.6), "acima_teto"],
  ["formato PT-PT", fmtDeg(3), "±3,0°"],
  // GAZE-02: modo frase
  ["hook: 2-4 palavras por linha", allSizes(phraseLines(hook)), true],
  ["hook: nada se perde", phraseLines(hook).join(" "), hook],
  ["hook: quebra na vírgula", phraseLines(hook).some((l) => l.endsWith("manhã,")), true],
  ["corpo: 2-4 palavras", allSizes(phraseLines(body)), true],
  ["corpo: fim de frase fecha a linha", phraseLines(body)[0], "Isto não é sorte."],
  ["corpo: travessão fica colado e não conta", phraseLines(body).some((l) => l.includes("pensar —")), true],
  ["corpo: nenhuma linha acaba em artigo ou preposição", phraseLines(body).every((l) => !/ (o|a|de|em|para)$/.test(l)), true],
  ["corpo: quebra antes de \"porque\"", phraseLines(body).some((l) => l.startsWith("porque")), true],
  ["CTA curto fica numa linha", phraseLines(cta), [cta]],
  ["uma palavra", phraseLines(longWord), [longWord]],
  ["vazio", phraseLines("   "), []],
  ["5 palavras partem em 2+3 ou 3+2", phraseLines("um dois três quatro cinco").map(wordCount).sort(), [2, 3]],
  ["parágrafos separados", phraseParagraphs(`${hook}\n\n${cta}`).length, 2],
  ["texto longo sem pontuação", allSizes(phraseLines("a casa do meu avô fica no alto da serra e tem vista para o mar todo o ano")), true],
];
let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`gaze: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
