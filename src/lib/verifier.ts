import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import { parseVerification, type Verification } from "@/lib/verifier-format";

/**
 * Leitura do verificador (VAR-04) em lote: os cartões pedem um guião cada; os pedidos do mesmo instante vão numa só
 * chamada a `content_verifications` (scripts.read no servidor, sessão ou código). Só os resultados encontrados ficam em
 * cache: um guião acabado de gerar pode ainda não ter a verificação.
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

  return (id: string, fresh = false): Promise<Verification | null> => {
    const hit = !fresh && cache.get(id);
    if (hit) return Promise.resolve(hit);
    return new Promise((resolve, reject) => {
      queue.push({ id, resolve, reject });
      if (!timer) timer = setTimeout(() => { void flush().catch((e: Error) => { queue.forEach((b) => b.reject(e)); }); }, 30);
    });
  };
}
