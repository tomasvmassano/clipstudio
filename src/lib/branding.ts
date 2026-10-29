"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/* Logótipo do cliente no bucket privado `branding` (ADR-0013). Só quem trabalha no cliente o vê (URL assinado, 1 h). */

export const LOGO_TYPES: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };
export const LOGO_MAX_BYTES = 512_000;

const cache = new Map<string, { url: string; until: number }>();

export function useLogoUrl(path: string | null | undefined) {
  const [got, setGot] = useState<{ path: string; url: string } | null>(null);
  const fresh = (p: string) => { const h = cache.get(p); return h && h.until > Date.now() ? h.url : null; };
  useEffect(() => {
    if (!path || fresh(path)) return;
    let alive = true;
    supabase().storage.from("branding").createSignedUrl(path, 3600).then(({ data }) => {
      if (!alive || !data?.signedUrl) return;
      cache.set(path, { url: data.signedUrl, until: Date.now() + 50 * 60 * 1000 });
      setGot({ path, url: data.signedUrl });
    });
    return () => { alive = false; };
  }, [path]);
  if (!path) return null;
  return fresh(path) ?? (got?.path === path ? got.url : null);
}

/** Valida e carrega; devolve o caminho novo (o nome muda a cada envio, por isso não há cache velha). */
export async function uploadLogo(ws: string, file: File): Promise<string> {
  const ext = LOGO_TYPES[file.type];
  if (!ext) throw new Error("O logótipo tem de ser PNG, JPG ou WebP.");
  if (file.size > LOGO_MAX_BYTES) throw new Error("O logótipo tem de ter até 500 KB.");
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) => b.toString(16).padStart(2, "0")).join("");
  const path = `${ws}/logo-${rand}.${ext}`;
  const { error } = await supabase().storage.from("branding").upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error(friendlyError(error.message));
  return path;
}

/** Apaga um logótipo antigo; se falhar devolve a mensagem (fica um ficheiro solto, sem efeito no cliente). */
export async function removeLogo(path: string): Promise<string | null> {
  const { error } = await supabase().storage.from("branding").remove([path]);
  cache.delete(path);
  return error ? friendlyError(error.message) : null;
}
