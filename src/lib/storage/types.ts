/*
 * Adaptador de armazenamento de objetos da biblioteca de media (ADR-0038). Só o servidor (Route Handlers) o usa:
 * quem pode o quê decidem antes as RPCs media_* (capacidade, cliente, flag, auditoria). O adaptador só executa.
 * Hoje: Supabase Storage (bucket privado `media`). Amanhã: Cloudflare R2 (S3) com URLs pré-assinados, sem mudar o resto.
 */

/** Para onde e como o browser envia os bytes (PUT direto ao armazenamento, com progresso). */
export type UploadTarget = { url: string; method: "PUT"; headers: Record<string, string>; expires_in_seconds: number };

export type SignedUrlOptions = { expiresIn: number; downloadName?: string };

export interface MediaStorage {
  readonly provider: "supabase" | "r2";
  /** URL de envio de uso único para um caminho que a RPC acabou de autorizar (versão pendente). */
  createUploadTarget(bucket: string, path: string, contentType: string): Promise<UploadTarget>;
  /** URL assinado curto para ler (pré-visualizar ou descarregar). */
  createSignedUrl(bucket: string, path: string, opts: SignedUrlOptions): Promise<string>;
  /** Lê o objeto em stream (para conferir o SHA-256 no servidor). null se não existir. */
  read(bucket: string, path: string): Promise<ReadableStream<Uint8Array> | null>;
  /** Apaga objetos; devolve os que confirmou apagar. */
  remove(bucket: string, paths: string[]): Promise<{ removed: string[]; error?: string }>;
}

export class StorageError extends Error {
  constructor(message: string, readonly status = 502) { super(message); }
}
