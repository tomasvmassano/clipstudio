import {
  LIMITS, activeAnnotations, addPenPoint, arrowHead, box, canAdd, contentRect, isMeaningful, normalize, parseAnnotation, penPath,
  timelineMarkers, toNormalized, toPixels, validateAnnotation, type Annotation, type Point, type Shape,
} from "../src/lib/annotation.ts";

const pen = (n: number): Shape => ({ type: "pen", color: "#ffffff", width: 0.004, points: Array.from({ length: n }, () => [0.5, 0.5] as Point) });
const rect: Shape = { type: "rect", color: "#FF3B30", width: 0.0061234, points: [[0.1, 0.1], [0.2, 0.123456]] };
const ok: Annotation = { v: 1, shapes: [rect, { type: "arrow", color: "#ffd60a", width: 0.008, points: [[0, 0], [1, 1]] }, pen(3)] };
const near = (a: number, b: number) => Math.abs(a - b) < 1e-6;

// vídeo 9:16 numa caixa 9:16 → caixa inteira; vídeo 16:9 numa caixa 9:16 → faixas em cima e em baixo
const r1 = contentRect(360, 640, 1080, 1920);
const r2 = contentRect(360, 640, 1920, 1080);
const r3 = contentRect(400, 300, 0, 0);
const cases: [string, unknown, unknown][] = [
  ["contain igual", JSON.stringify(r1), JSON.stringify({ x: 0, y: 0, w: 360, h: 640 })],
  ["contain largo: largura toda", r2.w, 360], ["contain largo: altura", near(r2.h, 202.5), true], ["contain largo: centrado", near(r2.y, 218.75), true],
  ["contain alto numa caixa larga", JSON.stringify(contentRect(800, 450, 1080, 1920).x > 0), "true"],
  ["sem metadados: caixa toda", JSON.stringify(r3), JSON.stringify({ x: 0, y: 0, w: 400, h: 300 })],
  ["caixa vazia", contentRect(0, 0, 10, 10).w, 0],
  ["normalizar centro", JSON.stringify(toNormalized(180, 320, r2)), JSON.stringify([0.5, 0.5])],
  ["normalizar fora (faixa preta) prende a 0", toNormalized(10, 5, r2)[1], 0],
  ["normalizar fora prende a 1", toNormalized(999, 999, r2)[0], 1],
  ["normalizar 4 casas", toNormalized(1, 1, { x: 0, y: 0, w: 3, h: 3 })[0], 0.3333],
  ["normalizar rect vazio", JSON.stringify(toNormalized(5, 5, { x: 0, y: 0, w: 0, h: 0 })), "[0,0]"],
  ["pixels", JSON.stringify(toPixels([0.5, 0.25], { x: 10, y: 10, w: 200, h: 400 })), "[100,100]"],
  ["mesmo ponto escala noutro ecrã", JSON.stringify(toPixels(toNormalized(180, 320, r2), contentRect(720, 1280, 1920, 1080))), JSON.stringify([360, 202.5])],
  ["caneta ignora ponto colado", addPenPoint([[0.5, 0.5]], [0.501, 0.5]).length, 1],
  ["caneta junta ponto afastado", addPenPoint([[0.5, 0.5]], [0.52, 0.5]).length, 2],
  ["caneta pára no limite", addPenPoint(pen(LIMITS.penPoints).points, [0.1, 0.1]).length, LIMITS.penPoints],
  ["clique não é seta", isMeaningful({ type: "arrow", color: "#fff", width: 0.004, points: [[0.5, 0.5], [0.501, 0.5]] }), false],
  ["arrasto é retângulo", isMeaningful(rect), true], ["toque de caneta conta", isMeaningful(pen(1)), true],
  ["cabe mais uma forma", canAdd([rect]), true],
  ["não cabe a 51.ª forma", canAdd(Array.from({ length: 50 }, () => rect)), false],
  ["não passa os 2000 pontos", canAdd([pen(500), pen(500), pen(500), pen(499)], 2), false],
  ["caixa em qualquer direção", JSON.stringify(box([0.4, 0.6], [0.2, 0.1])), JSON.stringify({ x: 0.2, y: 0.1, w: 0.2, h: 0.5 })],
  ["ponta da seta atrás da ponta", arrowHead([0, 0], [100, 0], 3).every((p) => p[0] < 100), true],
  ["ponta da seta simétrica", near(arrowHead([0, 0], [100, 0], 3)[0][1], -arrowHead([0, 0], [100, 0], 3)[1][1]), true],
  ["caminho da caneta", penPath([[0, 0], [0.5, 1]], { x: 0, y: 0, w: 100, h: 200 }), "M0.0 0.0L50.0 200.0"],
  ["caminho de um toque é visível", penPath([[0.5, 0.5]], { x: 0, y: 0, w: 100, h: 100 }).includes("l0.01"), true],
  ["válido", validateAnnotation(ok), null],
  ["tipo proibido", validateAnnotation({ v: 1, shapes: [{ ...rect, type: "text" }] }), "Tipo de forma não permitido."],
  ["coordenada > 1", validateAnnotation({ v: 1, shapes: [{ ...rect, points: [[0, 0], [1.1, 0]] }] }), "Coordenada fora do fotograma."],
  ["coordenada NaN", validateAnnotation({ v: 1, shapes: [{ ...rect, points: [[0, 0], [NaN, 0]] }] }), "Ponto inválido."],
  ["cor CSS", validateAnnotation({ v: 1, shapes: [{ ...rect, color: "red" }] }), "Cor inválida."],
  ["espessura", validateAnnotation({ v: 1, shapes: [{ ...rect, width: 0.5 }] }), "Espessura fora do intervalo."],
  ["seta com 3 pontos", validateAnnotation({ v: 1, shapes: [{ ...rect, type: "arrow", points: [[0, 0], [0, 0], [0, 0]] }] }), "Número de pontos inválido."],
  ["vazio", validateAnnotation({ v: 1, shapes: [] }), "Desenho vazio."],
  ["versão 2", validateAnnotation({ v: 2, shapes: [rect] }), "Formato desconhecido."],
  ["51 formas", validateAnnotation({ v: 1, shapes: Array.from({ length: 51 }, () => rect) }), "Máximo de 50 formas."],
  ["2001 pontos", validateAnnotation({ v: 1, shapes: [pen(500), pen(500), pen(500), pen(500), pen(1)] }), "Máximo de 2000 pontos."],
  ["2000 pontos", validateAnnotation({ v: 1, shapes: [pen(500), pen(500), pen(500), pen(500)] }), null],
  ["lista não é anotação", validateAnnotation([1]), "Formato desconhecido."],
  ["canónica: cor minúscula", normalize(ok).shapes[0].color, "#ff3b30"],
  ["canónica: 4 casas", normalize(ok).shapes[0].points[1][1], 0.1235],
  ["canónica: espessura 4 casas", normalize(ok).shapes[0].width, 0.0061],
  ["canónica: sem chaves extra", JSON.stringify(Object.keys(normalize({ v: 1, shapes: [{ ...rect, extra: 1 } as Shape] }).shapes[0])), JSON.stringify(["type", "color", "width", "points"])],
  ["parse null", parseAnnotation(null), null], ["parse lixo", parseAnnotation({ v: 1 }), null], ["parse ok", parseAnnotation(ok) === ok, true],
];

const comments = [
  { id: "a", t_ms: 10000, parent_id: null, annotation: ok, resolved_at: null },
  { id: "b", t_ms: 10400, parent_id: null, annotation: null, resolved_at: "2026-11-06" },
  { id: "c", t_ms: 30000, parent_id: null, annotation: ok, resolved_at: null },
  { id: "r", t_ms: 10000, parent_id: "a", annotation: ok, resolved_at: null },
  { id: "n", t_ms: null, parent_id: null, annotation: null, resolved_at: null },
];
cases.push(
  ["ativo no momento", activeAnnotations(comments, 10000).map((c) => c.id).join(), "a"],
  ["ativo +0,5 s", activeAnnotations(comments, 10500).map((c) => c.id).join(), "a"],
  ["fora da janela", activeAnnotations(comments, 10501).length, 0],
  ["só comentários com desenho e de topo", activeAnnotations(comments, 10200).map((c) => c.id).join(), "a"],
  ["marcas: sem duração nada", timelineMarkers(comments, 0).length, 0],
  ["marcas: juntas as próximas", JSON.stringify(timelineMarkers(comments, 60000).map((m) => m.ids)), JSON.stringify([["a", "b"], ["c"]])],
  ["marcas: posição %", near(timelineMarkers(comments, 60000)[1].pct, 50), true],
  ["marcas: desenho e aberto", JSON.stringify([timelineMarkers(comments, 60000)[0].drawn, timelineMarkers(comments, 60000)[0].open]), "[true,true]"],
  ["marcas: presas a 100%", timelineMarkers([{ id: "x", t_ms: 90000, parent_id: null }], 60000)[0].pct, 100],
);

let bad = 0; for (const [n, g, e] of cases) if (g !== e) { bad++; console.log("FAIL", n, JSON.stringify(g), "≠", JSON.stringify(e)); }
console.log(`annotation ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
