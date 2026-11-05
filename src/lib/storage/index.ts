import type { SupabaseClient } from "@supabase/supabase-js";
import { SUPABASE_KEY } from "@/lib/supabase";
import { SupabaseMediaStorage } from "./supabase";
import { StorageError, type MediaStorage } from "./types";
import { r2Storage } from "./r2";

export type { MediaStorage, UploadTarget } from "./types";
export { StorageError } from "./types";

/**
 * Escolhe a implementação pelo bucket que a RPC devolveu para essa versão (ADR-0047): "r2" é o Cloudflare R2, "media"
 * é o Supabase Storage. Cada versão fica onde nasceu, por isso ligar o R2 num cliente não parte os ficheiros antigos.
 * Sem as variáveis R2_* no servidor, falha fechado com uma mensagem clara (503) em vez de cair para outro armazenamento.
 */
export function mediaStorage(sb: SupabaseClient, bucket?: string): MediaStorage {
  if (bucket === "r2") return r2Storage();
  const provider = process.env.MEDIA_STORAGE_PROVIDER || "supabase";
  if (provider === "supabase") return new SupabaseMediaStorage(sb, SUPABASE_KEY);
  throw new StorageError(`Armazenamento "${provider}" ainda não está implementado.`, 501);
}

export { r2Storage, PART_BYTES, MULTIPART_FROM } from "./r2";

/** Até quantos bytes o servidor relê o objeto para conferir o SHA-256 (acima disso fica "declarado pelo browser"). */
export const VERIFY_MAX_BYTES = Number(process.env.MEDIA_VERIFY_MAX_BYTES || 100 * 1024 * 1024);
