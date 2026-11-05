import { createHash, createHmac } from "node:crypto";

/*
 * Assinatura AWS SigV4 mínima para o S3 do Cloudflare R2 (região "auto"). Só servidor: as chaves vêm do ambiente e
 * nunca chegam ao browser; o browser recebe apenas URLs pré-assinados de curta duração para um caminho autorizado.
 */
export type S3Creds = { accountId: string; accessKeyId: string; secretAccessKey: string; bucket: string };

const enc = (s: string) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
const encPath = (key: string) => key.split("/").map(enc).join("/");
const sha256hex = (s: string | Buffer) => createHash("sha256").update(s).digest("hex");
const hmac = (k: Buffer | string, s: string) => createHmac("sha256", k).update(s).digest();

function stamp(d: Date) {
  const iso = d.toISOString().replace(/[:-]|\.\d{3}/g, "");
  return { amz: iso, day: iso.slice(0, 8) };
}

function signingKey(secret: string, day: string, region = "auto") {
  return hmac(hmac(hmac(hmac("AWS4" + secret, day), region), "s3"), "aws4_request");
}

export function host(c: S3Creds) {
  return `${c.accountId}.r2.cloudflarestorage.com`;
}

function canonicalQuery(q: Record<string, string>) {
  return Object.keys(q).sort().map((k) => `${enc(k)}=${enc(q[k])}`).join("&");
}

/** Núcleo da pré-assinatura (exportado para o teste com o exemplo oficial da AWS). */
export function presignRaw(o: { host: string; path: string; region: string; accessKeyId: string; secretAccessKey: string; method: string;
                                 expiresIn: number; extra?: Record<string, string>; now: Date }): string {
  const { amz, day } = stamp(o.now);
  const scope = `${day}/${o.region}/s3/aws4_request`;
  const q: Record<string, string> = {
    ...(o.extra ?? {}),
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${o.accessKeyId}/${scope}`,
    "X-Amz-Date": amz,
    "X-Amz-Expires": String(Math.max(1, Math.min(604800, Math.floor(o.expiresIn)))),
    "X-Amz-SignedHeaders": "host",
  };
  const cq = canonicalQuery(q);
  const creq = [o.method, o.path, cq, `host:${o.host}\n`, "host", "UNSIGNED-PAYLOAD"].join("\n");
  const sts = ["AWS4-HMAC-SHA256", amz, scope, sha256hex(creq)].join("\n");
  const sig = createHmac("sha256", signingKey(o.secretAccessKey, day, o.region)).update(sts).digest("hex");
  return `https://${o.host}${o.path}?${cq}&X-Amz-Signature=${sig}`;
}

/** URL pré-assinado (query string) para GET, PUT ou UploadPart no R2. */
export function presign(c: S3Creds, method: "GET" | "PUT" | "HEAD", key: string, expiresIn: number,
                        extra: Record<string, string> = {}, now = new Date()): string {
  return presignRaw({ host: host(c), path: `/${enc(c.bucket)}/${encPath(key)}`, region: "auto", accessKeyId: c.accessKeyId,
                      secretAccessKey: c.secretAccessKey, method, expiresIn, extra, now });
}

/** Pedido assinado no cabeçalho (servidor → R2): HEAD, DELETE, criar/fechar/abortar envio por partes. */
export async function signedFetch(c: S3Creds, method: string, key: string, query: Record<string, string> = {},
                                  body?: string, headers: Record<string, string> = {}, now = new Date()): Promise<Response> {
  const { amz, day } = stamp(now);
  const h = host(c);
  const path = `/${enc(c.bucket)}/${encPath(key)}`;
  const payload = sha256hex(body ?? "");
  const all: Record<string, string> = { ...Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v])),
    host: h, "x-amz-content-sha256": payload, "x-amz-date": amz };
  const names = Object.keys(all).sort();
  const cq = canonicalQuery(query);
  const creq = [method, path, cq, names.map((n) => `${n}:${all[n].trim()}\n`).join(""), names.join(";"), payload].join("\n");
  const scope = `${day}/auto/s3/aws4_request`;
  const sts = ["AWS4-HMAC-SHA256", amz, scope, sha256hex(creq)].join("\n");
  const sig = createHmac("sha256", signingKey(c.secretAccessKey, day)).update(sts).digest("hex");
  const auth = `AWS4-HMAC-SHA256 Credential=${c.accessKeyId}/${scope}, SignedHeaders=${names.join(";")}, Signature=${sig}`;
  const { host: _h, ...send } = all;
  void _h;
  return fetch(`https://${h}${path}${cq ? "?" + cq : ""}`, { method, body, headers: { ...send, authorization: auth }, cache: "no-store" });
}

export function r2Creds(): S3Creds | null {
  const accountId = process.env.R2_ACCOUNT_ID, accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY, bucket = process.env.R2_BUCKET;
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) return null;
  return { accountId, accessKeyId, secretAccessKey, bucket };
}
