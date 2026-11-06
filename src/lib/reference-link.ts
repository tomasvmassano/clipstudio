/*
 * REF-01 (W10-04): identidade de um vídeo colado. Igual a reel_ref_key() na base e a engine/reference.py no motor; a base
 * é a autoridade (deteção de repetidos), isto só dá feedback imediato no campo "Colar link".
 */
const IG = /instagram\.com\/(?:[A-Za-z0-9._]{1,30}\/)?(?:reel|reels|p|tv)\/([A-Za-z0-9_-]{5,40})/i;
const TT = /tiktok\.com\/(?:@[A-Za-z0-9._-]{1,40}\/(?:video|photo)\/|v\/|embed\/(?:v2\/)?)([0-9]{6,25})/i;
const TT_SHORT = /^(?:https?:\/\/)?(?:vm|vt)\.tiktok\.com\/[A-Za-z0-9]+/i;

export function refKey(url: string): string | null {
  const s = url.trim();
  const ig = s.match(/^(?:https?:\/\/)?(?:www\.|m\.)?instagram\.com\//i) ? s.match(IG) : null;
  if (ig) return `instagram:${ig[1]}`;
  const tt = s.match(/^(?:https?:\/\/)?(?:www\.|m\.)?tiktok\.com\//i) ? s.match(TT) : null;
  if (tt) return `tiktok:${tt[1]}`;
  return null;
}

/** null quando o link serve; senão a mensagem a mostrar (PT-PT). */
export function pasteProblem(url: string): string | null {
  const s = url.trim();
  if (!s) return "Cola um link.";
  if (/\s/.test(s)) return "O link não pode ter espaços.";
  if (refKey(s) || TT_SHORT.test(s)) return null;
  return "Cola um link de um Reel do Instagram ou de um vídeo do TikTok. Para outros links usa Adicionar por link.";
}
