import type { SupabaseClient } from "@supabase/supabase-js";
import { StorageError, type MediaStorage, type SignedUrlOptions, type UploadTarget } from "./types";

/**
 * Implementação Supabase Storage. Recebe o cliente com a sessão de quem pede: as políticas de storage.objects
 * (_media_object_can) voltam a verificar cada operação, por isso uma rota mal usada não abre nada.
 */
export class SupabaseMediaStorage implements MediaStorage {
  readonly provider = "supabase" as const;
  constructor(private readonly sb: SupabaseClient, private readonly apiKey: string) {}

  async createUploadTarget(bucket: string, path: string, contentType: string): Promise<UploadTarget> {
    const { data, error } = await this.sb.storage.from(bucket).createSignedUploadUrl(path);
    if (error || !data) throw new StorageError(`Não consegui preparar o envio: ${error?.message ?? "sem resposta"}`);
    // O URL assinado vale 2 h (Supabase); a versão pendente vale mais (24 h): retomar pede um URL novo.
    return { url: data.signedUrl, method: "PUT", headers: { "content-type": contentType, "x-upsert": "false", apikey: this.apiKey }, expires_in_seconds: 7200 };
  }

  async createSignedUrl(bucket: string, path: string, opts: SignedUrlOptions): Promise<string> {
    const { data, error } = await this.sb.storage.from(bucket)
      .createSignedUrl(path, opts.expiresIn, opts.downloadName ? { download: opts.downloadName } : undefined);
    if (error || !data?.signedUrl) throw new StorageError(`Não consegui gerar o link: ${error?.message ?? "sem resposta"}`);
    return data.signedUrl;
  }

  async read(bucket: string, path: string): Promise<ReadableStream<Uint8Array> | null> {
    const { data, error } = await this.sb.storage.from(bucket).download(path);
    if (error || !data) return null;
    return data.stream();
  }

  async remove(bucket: string, paths: string[]): Promise<{ removed: string[]; error?: string }> {
    if (paths.length === 0) return { removed: [] };
    const { data, error } = await this.sb.storage.from(bucket).remove(paths);
    return { removed: (data ?? []).map((o) => o.name), error: error?.message };
  }
}
