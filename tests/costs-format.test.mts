import { convert, csvFor, customError, duration, money, periodArgs, tokens, trend } from "../src/lib/costs-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => {
  n++; const g = JSON.stringify(got); const e = JSON.stringify(exp);
  if (g !== e) { bad++; console.log("FAIL", name, g, "esperado", e); }
};
const fx = { quote: "AED", rate: 4.0, as_of: "2026-11-01", source: "BCE" };
const nb = (s: string) => s.replace(/ | /g, " ");

eq("EUR passa igual", convert(1.25, "EUR", null), 1.25);
eq("AED com taxa", convert(1.25, "AED", fx), 5);
eq("AED sem taxa: nunca inventa", convert(1.25, "AED", null), null);
eq("custo desconhecido continua desconhecido", convert(null, "AED", fx), null);
eq("money desconhecido nunca é zero", money(null, "EUR", null), "sem custo conhecido");
eq("money AED sem taxa", money(2, "AED", null), "sem taxa EUR/AED");
eq("money EUR", nb(money(1.5, "EUR", null)), "1,50 €");
eq("tokens pequenos", tokens(950), "950");
eq("tokens mil", tokens(1234), "1,2 mil");
eq("tokens milhões", tokens(3_400_000), "3,4 M");
eq("tokens nulos", tokens(null), "-");
eq("duração s", duration(42), "42 s");
eq("duração min", duration(600), "10 min");
eq("duração h", duration(3600), "1 h");
eq("duração h min", duration(5400), "1 h 30 min");
eq("tendência subida", trend(1.5, 1.0, 3).text, "+50% face ao período anterior");
eq("tendência descida", trend(0.5, 1.0, 3).kind, "down");
eq("tendência estável abaixo de 1%", trend(1.005, 1.0, 2).kind, "flat");
eq("sem anterior não inventa percentagem", trend(2, 0, 0), { kind: "new", pct: null, text: "sem atividade no período anterior" });
eq("nada nos dois", trend(0, 0, 0).kind, "none");
eq("anterior só com desconhecidos", trend(1, 0, 2).pct, null);
eq("período fixo", periodArgs({ days: 7 }), { p_days: 7, p_from: null, p_to: null });
eq("período personalizado", periodArgs({ from: "2026-10-01", to: "2026-10-31" }), { p_days: null, p_from: "2026-10-01", p_to: "2026-10-31" });
eq("personalizado válido", customError("2026-10-01", "2026-10-31"), null);
eq("personalizado invertido", customError("2026-10-31", "2026-10-01"), "A data de início tem de ser anterior ou igual à data de fim.");
eq("personalizado vazio", customError("", "2026-10-01"), "Escolhe a data de início e a data de fim.");
eq("personalizado acima de 366 dias", customError("2025-01-01", "2026-10-01"), "O período pode ter no máximo 366 dias.");
eq("366 dias aceite", customError("2024-01-01", "2024-12-31"), null);

const data = {
  workspaces: [{ id: "a", name: "=Cliente A", currency: "EUR", cost: 1.5, prev_cost: 0.5, jobs: 3, prev_jobs: 1, jobs_unknown: 1, tokens_in: 10, tokens_out: 5, calls_cost: 1.2 }],
  agents: [{ key: "writer", name: "Escritor", calls: 2, calls_unknown: 0, cost: 1.1, prev_cost: 0.25, prev_calls: 1, tokens_in: 600, tokens_out: 400 }],
  models: [],
  runs: [{ id: "r1", workspace_id: "a", workspace_name: "A", kind: "daily_pipeline", status: "failed", cost_eur: null, cost_known: false, tokens_in: null, tokens_out: null,
    attempts: 2, started_at: null, finished_at: "2026-11-05T10:00:00Z", duration_s: null, calls_cost: null }],
};
const w = csvFor("workspaces", data, "EUR", null);
eq("csv clientes: cabeçalho EUR", w.header[1], "custo_eur");
eq("csv clientes: linha", w.rows[0].slice(0, 3), ["=Cliente A", 1.5, 0.5]);
const wa = csvFor("workspaces", data, "AED", fx);
eq("csv AED leva taxa e data", wa.header.slice(1, 5), ["custo_eur", "custo_aed", "taxa_eur_aed", "data_taxa"]);
eq("csv AED valores", wa.rows[0].slice(1, 5), [1.5, 6, 4, "2026-11-01"]);
eq("csv AED sem taxa fica só em EUR", csvFor("workspaces", data, "AED", null).header.includes("custo_aed"), false);
eq("csv agentes", csvFor("agents", data, "EUR", null).rows[0].slice(0, 3), ["Escritor", "writer", 1.1]);
eq("csv modelos vazio", csvFor("models", data, "EUR", null).rows.length, 0);
const r = csvFor("runs", data, "EUR", null);
eq("csv execuções: desconhecido vazio e rotulado", [r.rows[0][4], r.rows[0][r.rows[0].length - 1], r.rows[0][2], r.rows[0][3]], [null, "sem custo conhecido", "Guiões do dia", "Falhou"]);
console.log(`costs-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
