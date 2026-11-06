import assert from "node:assert/strict";
import { autoReasonLabel, cameraProblem, rowState } from "../src/lib/package-script-format.ts";

const clip = (o: Record<string, unknown> = {}) => ({ asset_id: "a", content_id: "g", camera: "front", session_id: null, source: "upload", linked_label: null,
  linked_at: "", title: "t", name: "g01_frente.mp4", state: "pronta", storage: "r2", version_id: "vf", version_no: 1, duration: 90, ...o }) as never;
const job = (o: Record<string, unknown> = {}) => ({ id: "j", status: "done", progress: null, last_error: null, created_label: null, created_at: "", worker_seen: true,
  origin: "auto", front_name: "g01_frente.mp4", side_name: "g01_lado.mp4", front_version: "vf", side_version: "vs", result: null, outputs: [], ...o }) as never;
const side = clip({ camera: "side", name: "g01_lado.mp4", version_id: "vs" });

assert.equal(rowState({ front: null, side: null, job: null }), "sem_gravacoes");
assert.equal(rowState({ front: clip(), side: null, job: null }), "falta_lado");
assert.equal(rowState({ front: null, side, job: null }), "falta_frente");
assert.equal(rowState({ front: clip({ state: "pendente" }), side, job: null }), "a_verificar");
assert.equal(rowState({ front: clip({ state: "falhou" }), side, job: null }), "gravacao_falhou");
assert.equal(rowState({ front: clip(), side, job: null }), "pronto_para_pacote");
assert.equal(rowState({ front: clip(), side, job: job() }), "pacote_pronto");
assert.equal(rowState({ front: clip(), side, job: job({ status: "running" }) }), "a_preparar");
assert.equal(rowState({ front: clip(), side, job: job({ status: "queued" }) }), "na_fila");
assert.equal(rowState({ front: clip(), side, job: job({ status: "dead" }) }), "pacote_falhou");
// versão nova da gravação (mesmo nome): o pacote antigo já não conta
assert.equal(rowState({ front: clip({ version_id: "vf2" }), side, job: job() }), "pronto_para_pacote");
// gravação nova ainda a verificar: mostra o pacote anterior até ela ficar pronta
assert.equal(rowState({ front: clip({ version_id: "vf2", state: "pendente" }), side, job: job() }), "pacote_pronto");

assert.equal(autoReasonLabel(null), null);
assert.equal(autoReasonLabel("sem_permissao"), "quem ligou o automático já não tem permissão para pedir pacotes");
assert.match(autoReasonLabel("nome_repetido")!, /mesmo nome/);
assert.equal(autoReasonLabel("outra coisa"), "outra coisa");

assert.equal(cameraProblem(["front", "side", ""]), null);
assert.equal(cameraProblem(["front", "front"]), "Escolhe no máximo um ficheiro para cada câmara.");
assert.equal(cameraProblem(["", ""]), null);
console.log("package-script: ok");
