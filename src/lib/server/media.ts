import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { friendlyError } from "@/lib/access";
import { StorageError } from "@/lib/storage";

/* Apoio às rotas /api/media (ADR-0038): erros estáveis das RPCs → HTTP, sem cache, SHA-256 em stream. */

const STATUS: Record<string, number> = { "42501": 403, "28000": 401, P0002: 404, "22023": 422, "55000": 409, PT409: 409 };

export type RpcFail = { code?: string; message: string; details?: string | null };

export function fail(e: RpcFail | StorageError | Error, fallback = 500) {
  if (e instanceof StorageError) return NextResponse.json({ error: e.message, code: "storage" }, { status: e.status, headers: { "Cache-Control": "no-store" } });
  const r = e as RpcFail;
  const status = (r.code && STATUS[r.code]) || fallback;
  return NextResponse.json({ error: r.details || friendlyError(r.message), code: r.code ?? "erro" }, { status, headers: { "Cache-Control": "no-store" } });
}

export const ok = (body: unknown) => NextResponse.json(body, { headers: { "Cache-Control": "no-store" } });

export async function rpc<T>(sb: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<{ data: T; error: null } | { data: null; error: RpcFail }> {
  const { data, error } = await sb.rpc(fn, args);
  return error ? { data: null, error } : { data: data as T, error: null };
}

/** SHA-256 hex de um stream, parando se passar do tamanho esperado (nunca lê mais do que o declarado + 1 byte). */
export async function sha256Stream(stream: ReadableStream<Uint8Array>, maxBytes: number): Promise<{ sha256: string; bytes: number } | null> {
  const h = createHash("sha256");
  const reader = stream.getReader();
  let bytes = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > maxBytes) { await reader.cancel(); return null; }
    h.update(value);
  }
  return { sha256: h.digest("hex"), bytes };
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const WS = /^[a-z0-9_-]{1,60}$/;

export async function body(req: Request): Promise<Record<string, unknown>> {
  try { const b = await req.json(); return b && typeof b === "object" ? (b as Record<string, unknown>) : {}; } catch { return {}; }
}
