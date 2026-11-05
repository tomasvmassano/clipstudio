/* Registo da publicação manual (FR-12-02, ADR-0054): link público do post por plataforma. Regra pura, igual a
 * public._pub_post_url no servidor (que é quem decide); aqui só avisa enquanto se escreve. Sem dependências, testável em node. */

export type PostPlatform = "instagram" | "tiktok" | "youtube";
export type PostUrl = { external_id: string; handle: string | null; url: string };

const IG = /^https?:\/\/(?:www\.|m\.)?instagram\.com\/(?:([A-Za-z0-9._]{1,30})\/)?(reels?|p|tv)\/([A-Za-z0-9_-]{5,40})\/?(?:[?#].*)?$/i;
const TT = /^https?:\/\/(?:www\.|m\.)?tiktok\.com\/@([A-Za-z0-9._]{1,40})\/(?:video|photo)\/([0-9]{8,25})\/?(?:[?#].*)?$/i;
const YT = [
  /^https?:\/\/(?:www\.|m\.)?youtube\.com\/shorts\/([A-Za-z0-9_-]{11})\/?(?:[?#].*)?$/i,
  /^https?:\/\/(?:www\.|m\.)?youtube\.com\/watch\?(?:[^#]*&)?v=([A-Za-z0-9_-]{11})(?:[&#].*)?$/i,
  /^https?:\/\/youtu\.be\/([A-Za-z0-9_-]{11})\/?(?:[?#].*)?$/i,
];

/** Devolve o ID do post, a conta (se o link a traz) e o link canónico; null se não for um post desta plataforma. */
export function parsePostUrl(platform: PostPlatform, raw: string): PostUrl | null {
  const u = (raw ?? "").trim();
  if (!u || u.length > 1000 || /\s/.test(u)) return null;
  if (platform === "instagram") {
    const m = IG.exec(u);
    if (!m) return null;
    const kind = ["reel", "reels"].includes(m[2].toLowerCase()) ? "reel" : m[2].toLowerCase();
    return { external_id: m[3], handle: m[1] ? m[1].toLowerCase() : null, url: `https://www.instagram.com/${kind}/${m[3]}/` };
  }
  if (platform === "tiktok") {
    const m = TT.exec(u);
    if (!m) return null;
    const h = m[1].toLowerCase();
    return { external_id: m[2], handle: h, url: `https://www.tiktok.com/@${h}/video/${m[2]}` };
  }
  if (platform === "youtube") {
    for (const re of YT) {
      const m = re.exec(u);
      if (m) return { external_id: m[1], handle: null, url: `https://www.youtube.com/shorts/${m[1]}` };
    }
  }
  return null;
}

export const POST_URL_HINT: Record<PostPlatform, string> = {
  instagram: "Cola o link do post do Instagram (instagram.com/reel/... ou /p/...).",
  tiktok: "Cola o link completo do TikTok (tiktok.com/@conta/video/...). Links curtos vm.tiktok.com não servem: abre-o e copia o link completo.",
  youtube: "Cola o link do YouTube (youtube.com/shorts/..., youtube.com/watch?v=... ou youtu.be/...).",
};

/** Problema do link para mostrar ao lado do campo (null = parece bem; o servidor volta a verificar). */
export function postUrlProblem(platform: PostPlatform, raw: string, accountHandle: string): string | null {
  if (!raw.trim()) return null;
  const p = parsePostUrl(platform, raw);
  if (!p) return POST_URL_HINT[platform];
  if (p.handle && p.handle !== accountHandle.toLowerCase()) return `Este link é de @${p.handle}, não de @${accountHandle}.`;
  return null;
}
