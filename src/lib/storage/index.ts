import type { SupabaseClient } from "@supabase/supabase-js";
import { SUPABASE_KEY } from "@/lib/supabase";
import { SupabaseMediaStorage } from "./supabase";
import { StorageError, type MediaStorage } from "./types";

export type { MediaStorage, UploadTarget } from "./types";
export { StorageError } from "./types";

/**
 * Escolhe a implementação (MEDIA_STORAGE_PROVIDER, por defeito "supabase"). "r2" ainda não existe: falha fechado com
 * uma mensagem clara em vez de cair para outro armazenamento (ADR-0038).
 */
export function mediaStorage(sb: SupabaseClient): MediaStorage {
  const provider = process.env.MEDIA_STORAGE_PROVIDER || "supabase";
  if (provider === "supabase") return new SupabaseMediaStorage(sb, SUPABASE_KEY);
  throw new StorageError(`Armazenamento "${provider}" ainda não está implementado.`, 501);
}

/** Até quantos bytes o servidor relê o objeto para conferir o SHA-256 (acima disso fica "declarado pelo browser"). */
export const VERIFY_MAX_BYTES = Number(process.env.MEDIA_VERIFY_MAX_BYTES || 100 * 1024 * 1024);
