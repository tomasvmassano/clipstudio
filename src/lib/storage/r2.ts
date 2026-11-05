import { presign, r2Creds, signedFetch, type S3Creds } from "./sigv4";
import { StorageError, type MediaStorage, type SignedUrlOptions, type UploadTarget } from "./types";

/** Tamanho de cada parte no envio por partes (64 MiB: 50 GiB cabem em 800 partes, abaixo do limite de 10 000). */
export const PART_BYTES = 64 * 1024 * 1024;
/** Acima disto o envio é por partes (um PUT simples no R2 vai até 5 GiB; partes também retomam melhor). */
export const MULTIPART_FROM = 256 * 1024 * 1024;

export type MultipartTarget = { upload_id: string; part_bytes: number; parts: { n: number; url: string }[]; expires_in_seconds: number };

/**
 * Cloudflare R2 (S3). As RPCs media_* já decidiram quem pode o quê e devolvem o caminho; isto só assina URLs de curta
 * duração para esse caminho. O bucket lógico na base é "r2"; o bucket real vem de R2_BUCKET.
 */
export class R2MediaStorage implements MediaStorage {
  readonly provider = "r2" as const;
  constructor(private readonly c: S3Creds) {}

  async createUploadTarget(_bucket: string, path: string, contentType: string): Promise<UploadTarget> {
    const url = presign(this.c, "PUT", path, 7200);
    return { url, method: "PUT", headers: { "content-type": contentType }, expires_in_seconds: 7200 };
  }

  async createSignedUrl(_bucket: string, path: string, opts: SignedUrlOptions): Promise<string> {
    const extra: Record<string, string> = {};
    if (opts.downloadName) extra["response-content-disposition"] = `attachment; filename="${opts.downloadName.replace(/["\\\r\n]/g, "_")}"`;
    return presign(this.c, "GET", path, opts.expiresIn, extra);
  }

  async read(_bucket: string, path: string): Promise<ReadableStream<Uint8Array> | null> {
    const r = await fetch(presign(this.c, "GET", path, 300), { cache: "no-store" });
    return r.ok && r.body ? r.body : null;
  }

  async head(path: string): Promise<{ size: number; type: string | null } | null> {
    const r = await signedFetch(this.c, "HEAD", path);
    if (r.status === 404) return null;
    if (!r.ok) throw new StorageError(`R2 respondeu ${r.status} ao conferir o ficheiro.`);
    return { size: Number(r.headers.get("content-length") ?? -1), type: r.headers.get("content-type") };
  }

  async remove(_bucket: string, paths: string[]): Promise<{ removed: string[]; error?: string }> {
    const removed: string[] = []; let error: string | undefined;
    for (const p of paths) {
      const r = await signedFetch(this.c, "DELETE", p);
      if (r.ok || r.status === 404) removed.push(p); else error = `R2 ${r.status}`;
    }
    return { removed, error };
  }

  async createMultipart(path: string, contentType: string, size: number): Promise<MultipartTarget> {
    const r = await signedFetch(this.c, "POST", path, { uploads: "" }, undefined, { "content-type": contentType });
    const xml = await r.text();
    const id = /<UploadId>([^<]+)<\/UploadId>/.exec(xml)?.[1];
    if (!r.ok || !id) throw new StorageError(`Não consegui começar o envio por partes (R2 ${r.status}).`);
    return this.partUrls(path, id, size);
  }

  partUrls(path: string, uploadId: string, size: number, only?: number[]): MultipartTarget {
    const total = Math.max(1, Math.ceil(size / PART_BYTES));
    if (total > 10000) throw new StorageError("Ficheiro grande demais para o envio por partes.", 413);
    const ns = (only?.length ? only : Array.from({ length: total }, (_, i) => i + 1)).filter((n) => n >= 1 && n <= total);
    return { upload_id: uploadId, part_bytes: PART_BYTES, expires_in_seconds: 21600,
      parts: ns.map((n) => ({ n, url: presign(this.c, "PUT", path, 21600, { partNumber: String(n), uploadId }) })) };
  }

  async completeMultipart(path: string, uploadId: string, parts: { n: number; etag: string }[]): Promise<void> {
    const body = "<CompleteMultipartUpload>" + [...parts].sort((a, b) => a.n - b.n)
      .map((p) => `<Part><PartNumber>${p.n}</PartNumber><ETag>${p.etag.replace(/[<>&]/g, "")}</ETag></Part>`).join("") + "</CompleteMultipartUpload>";
    const r = await signedFetch(this.c, "POST", path, { uploadId }, body, { "content-type": "application/xml" });
    const xml = await r.text();
    if (!r.ok || /<Error>/.test(xml)) throw new StorageError(`R2 recusou juntar as partes: ${/<Message>([^<]+)/.exec(xml)?.[1] ?? r.status}`);
  }

  async abortMultipart(path: string, uploadId: string): Promise<void> {
    await signedFetch(this.c, "DELETE", path, { uploadId });
  }
}

export function r2Storage(): R2MediaStorage {
  const c = r2Creds();
  if (!c) throw new StorageError("O armazenamento de vídeo (R2) ainda não está configurado no servidor.", 503);
  return new R2MediaStorage(c);
}
