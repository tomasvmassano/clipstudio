import { WS_A, sql } from "./env";

/* Liga flags no cliente A durante uma spec e repõe exatamente o estado anterior no fim (a base local é partilhada). */
let saved: { keys: string[]; rows: string[] } | null = null;

export function flagsOnForA(keys: string[]) {
  const list = keys.map((k) => `'${k}'`).join(",");
  saved = { keys, rows: sql(`select key || '=' || stage from feature_flags where workspace_id = '${WS_A}' and key in (${list})`) };
  sql(`delete from feature_flags where workspace_id = '${WS_A}' and key in (${list});
       insert into feature_flags (key, organization_id, workspace_id, stage)
         select k, c.organization_id, c.id, 'all' from clients c, unnest(array[${list}]) k where c.id = '${WS_A}'`);
}

export function restoreFlags() {
  if (!saved) return;
  const list = saved.keys.map((k) => `'${k}'`).join(",");
  sql(`delete from feature_flags where workspace_id = '${WS_A}' and key in (${list})`);
  for (const r of saved.rows) {
    const [k, stage] = r.split("=");
    sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${k}', organization_id, id, '${stage}' from clients where id = '${WS_A}'`);
  }
  saved = null;
}
