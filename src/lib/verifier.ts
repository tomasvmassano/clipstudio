import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import { fetchMyFlags } from "@/lib/flags";
import { parseVerification, type Verification } from "@/lib/verifier-format";

/** "off": a flag `scripts.verifier` está desligada para esta pessoa no cliente (ou a app ainda não tem a migração). */
export type VerificationLookup = Verification | null | "off";
export const VERIFIER_FLAG = "scripts.verifier";

/**
 * Leitura do verificador (VAR-04) em lote: os cartões pedem um guião cada; os pedidos do mesmo instante vão numa só
 * chamada a `content_verifications` (scripts.read no servidor, sessão ou código). Só os resultados encontrados ficam em
 * cache: um guião acabado de gerar pode ainda não ter a verificação. Atrás da flag `scripts.verifier` (CAP-09): desligada,
 * não chama o servidor.
 */
export function verificationLoader(access: Access) {
  const cache = new Map<string, Verification>();
  let queue: { id: string; resolve: (v: Verification | null) => void; reject: (e: Error) => void }[] = [];
  let timer: ReturnType<typeof setTimeout> | null = null;

  const flush = async () => {
    const batch = queue; queue = []; timer = null;
    const ids = [...new Set(batch.map((b) => b.id))];
    for (let k = 0; k < ids.length; k += 200) {
      const part = ids.slice(k, k + 200);
      const { data, error } = await supabase().rpc("content_verifications", { p_ws: access.ws, p_ids: part, p_token: access.token });
      const mine = batch.filter((b) => part.includes(b.id));
      if (error) { const e = new Error(friendlyError(error.message)); mine.forEach((b) => b.reject(e)); continue; }
      const map = (data ?? {}) as Record<string, unknown>;
      for (const b of mine) {
        const v = parseVerification(map[b.id]);
        if (v) cache.set(b.id, v);
        b.resolve(v);
      }
    }
  };

  let on: Promise<boolean> | null = null;
  return async (id: string, fresh = false): Promise<VerificationLookup> => {
    on ??= fetchMyFlags(access.ws, access.token).then((l) => l.includes(VERIFIER_FLAG), () => false);
    if (!(await on)) return "off";
    const hit = !fresh && cache.get(id);
    if (hit) return hit;
    return new Promise<Verification | null>((resolve, reject) => {
      queue.push({ id, resolve, reject });
      if (!timer) timer = setTimeout(() => { void flush().catch((e: Error) => { queue.forEach((b) => b.reject(e)); }); }, 30);
    });
  };
}
