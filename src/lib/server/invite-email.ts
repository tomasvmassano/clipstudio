/**
 * Envio do email do convite (W1-14, ADR-0023). Só no servidor.
 * Com RESEND_API_KEY e INVITE_FROM definidos no Vercel, envia pelo Resend; sem eles devolve { sent: false }
 * e a app mostra o link para copiar (alternativa manual explícita, AGENTS §8). A chave nunca vai para o browser.
 */
export type InviteLink = { token: string; email: string; kind: "agency" | "workspace"; target: string; role: string; inviter: string; expires_at: string };

const ROLE: Record<string, string> = {
  workspace_owner: "dono do cliente", workspace_admin: "admin do cliente", manager: "gestor", contributor: "colaborador",
  reviewer: "revisor", viewer: "leitura", agency_admin: "admin da agência", agency_manager: "gestor da agência", agency_member: "membro da agência",
};

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export function inviteMessage(inv: InviteLink, link: string) {
  const onde = inv.kind === "agency" ? `a equipa da agência ${inv.target}` : `o espaço de ${inv.target}`;
  const papel = ROLE[inv.role] ?? inv.role;
  const ate = new Date(inv.expires_at).toLocaleDateString("pt-PT", { day: "numeric", month: "long", timeZone: "Europe/Lisbon" });
  const subject = `${inv.inviter} convidou-te para ${inv.target} no ClipStudio`;
  const text = [
    `Olá,`, ``,
    `${inv.inviter} convidou-te para ${onde} no ClipStudio, como ${papel}.`, ``,
    `Para aceitar ou recusar, abre este link:`, link, ``,
    `Entra ou cria conta com este email (${inv.email}). O convite é válido até ${ate}.`,
    `Se não estavas à espera deste convite, podes ignorar este email ou recusá-lo no link.`,
  ].join("\n");
  const html = `<!doctype html><html><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#111;max-width:520px;margin:0 auto;padding:24px">
<p>Olá,</p>
<p><strong>${esc(inv.inviter)}</strong> convidou-te para ${esc(onde)} no ClipStudio, como <strong>${esc(papel)}</strong>.</p>
<p style="margin:28px 0"><a href="${esc(link)}" style="background:#111;color:#fff;padding:12px 20px;border-radius:8px;text-decoration:none;display:inline-block">Ver o convite</a></p>
<p style="color:#555;font-size:14px">Entra ou cria conta com este email (${esc(inv.email)}). O convite é válido até ${esc(ate)}.</p>
<p style="color:#555;font-size:14px">Se não estavas à espera deste convite, podes ignorar este email ou recusá-lo no link.</p>
<p style="color:#888;font-size:12px;word-break:break-all">${esc(link)}</p>
</body></html>`;
  return { subject, text, html };
}

export async function sendInviteEmail(inv: InviteLink, link: string): Promise<{ sent: boolean; error?: string }> {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.INVITE_FROM;
  if (!key || !from) return { sent: false };
  const { subject, text, html } = inviteMessage(inv, link);
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Idempotency-Key": `invite-${inv.token.slice(0, 16)}` },
      body: JSON.stringify({ from, to: [inv.email], subject, text, html }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!r.ok) return { sent: false, error: `O serviço de email recusou o envio (${r.status}).` };
    return { sent: true };
  } catch {
    return { sent: false, error: "O serviço de email não respondeu." };
  }
}
