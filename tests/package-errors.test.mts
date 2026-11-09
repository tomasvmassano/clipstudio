import assert from "node:assert/strict";
import { packageErrorText } from "../src/lib/package-errors.ts";

let n = 0;
const t = (name: string, f: () => void) => { f(); n++; };

t("memória (sinal 9)", () => assert.match(packageErrorText("ffmpeg falhou (-9): "), /sem memória/));
t("worker parou", () => assert.match(packageErrorText("worker deixou de responder"), /parou a meio/));
t("sem som", () => assert.match(packageErrorText("não consegui tirar o som: Stream map '' matches no streams."), /som da câmara escolhida para a lapela/));
t("gravação em falta", () => assert.match(packageErrorText("gravacao_nao_encontrada"), /Biblioteca/));
t("genérico, incluindo o TypeError de 2026-11-06", () => assert.match(packageErrorText("TypeError: open() got an unexpected keyword argument 'metadata_errors'"), /não conseguiu acabar/));
t("vazio", () => assert.match(packageErrorText(null), /não conseguiu acabar/));

console.log(`package-errors: ${n}/${n}`);
