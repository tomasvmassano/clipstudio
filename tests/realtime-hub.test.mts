// Teste do gestor de canais (ADR-0019) com um cliente falso que se comporta como o Supabase:
// o mesmo nome devolve o mesmo canal e .on() depois de .subscribe() lança (o erro que partiu /c/numeiro).
import { createChannelHub } from "../src/lib/realtime-hub.ts";

class FakeChannel {
  subscribed = false; handlers: ((p: unknown) => void)[] = []; removed = false;
  on(fn: (p: unknown) => void) { if (this.subscribed) throw new Error("cannot add callbacks after subscribe()"); this.handlers.push(fn); return this; }
  subscribe() { this.subscribed = true; return this; }
  fire(p: unknown) { this.handlers.forEach((h) => h(p)); }
}
const registry = new Map<string, FakeChannel>();
const fake = { channel: (n: string) => { let c = registry.get(n); if (!c) { c = new FakeChannel(); registry.set(n, c); } return c; },
               removeChannel: (c: FakeChannel) => { c.removed = true; for (const [k, v] of registry) if (v === c) registry.delete(k); } };

let ok = 0, bad = 0;
const check = (name: string, cond: boolean) => { if (cond) ok++; else { bad++; console.log("FAIL", name); } };
const tick = () => new Promise((r) => setTimeout(r, 0));

// sem o gestor, o padrão antigo rebenta (garante que o falso imita o erro real)
let threw = false;
try { fake.channel("x").on(() => {}).subscribe(); fake.channel("x").on(() => {}).subscribe(); } catch { threw = true; }
check("o cliente falso reproduz o erro do Supabase", threw);
registry.clear();

const hub = createChannelHub<FakeChannel>((c) => fake.removeChannel(c));
const factory = (n: string, emit: (p: unknown) => void) => fake.channel(n).on(emit).subscribe();
const got: string[] = [];
const off1 = hub.listen("guioes-numeiro", factory, () => got.push("a"));
const off2 = hub.listen("guioes-numeiro", factory, () => got.push("b"));
await tick();
check("dois ouvintes do mesmo canal não rebentam e partilham um canal", registry.size === 1 && hub.size() === 1);
registry.get("guioes-numeiro")!.fire({});
check("cada ouvinte recebe o evento", got.join() === "a,b");
off1();
check("sair um ouvinte não fecha o canal", registry.size === 1 && !registry.get("guioes-numeiro")!.removed);
const ch = registry.get("guioes-numeiro")!;
off2();
check("o último a sair fecha o canal", ch.removed && hub.size() === 0);
const off3 = hub.listen("guioes-numeiro", factory, () => got.push("c"));
await tick();
check("voltar a abrir depois de fechar cria um canal novo", registry.size === 1 && registry.get("guioes-numeiro") !== ch);
off3();
const off4 = hub.listen("agents:numeiro", async (n, emit) => { await tick(); return factory(n, emit); }, () => {});
off4(); await tick(); await tick();
check("sair antes de o canal abrir fecha-o quando abre (sem fugas)", registry.size === 0);
const quiet = console.error; console.error = () => {};
const offErr = hub.listen("falha", () => { throw new Error("sem rede"); }, () => {});
await tick(); await tick();
console.error = quiet;
check("falha ao abrir o canal não lança para a página", true);
offErr();
hub.listen("boom", factory, () => { throw new Error("ouvinte com erro"); });
const offOk = hub.listen("boom", factory, () => got.push("ok"));
await tick();
const origError = console.error; console.error = () => {};
registry.get("boom")!.fire({});
console.error = origError;
check("um ouvinte que lança não impede os outros", got.includes("ok"));
offOk();
console.log(`realtime-hub ${ok}/${ok + bad}`);
if (bad) process.exit(1);
