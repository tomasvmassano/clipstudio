import { NextResponse, type NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { sendInviteEmail, type InviteLink } from "@/lib/server/invite-email";
import { friendlyError } from "@/lib/access";

/**
 * POST /api/invites/:id/send · envia (ou reenvia) o email do convite (FR-13-01, ADR-0023).
 * Quem pode e quantas vezes decide a base de dados (invitation_issue_link, com a sessão de quem pede).
 * Sem serviço de email configurado devolve o link para a pessoa o mandar à mão.
 */
export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return NextResponse.json({ error: "Convite inválido." }, { status: 400 });
  const sb = await serverSupabase();
  const { data, error } = await sb.rpc("invitation_issue_link", { p_id: id });
  if (error) {
    const status = error.code === "42501" ? 403 : error.code === "28000" ? 401 : error.code === "PT429" ? 429 : error.code === "22023" ? 409 : 500;
    return NextResponse.json({ error: friendlyError(error.message) }, { status });
  }
  const inv = data as InviteLink;
  const base = process.env.APP_URL || req.nextUrl.origin;
  const link = `${base.replace(/\/$/, "")}/convite?t=${inv.token}`;
  const mail = await sendInviteEmail(inv, link);
  // Sem envio (não configurado ou falhou), quem convidou recebe o link para o mandar por outro meio.
  return NextResponse.json(
    { sent: mail.sent, email: inv.email, expires_at: inv.expires_at, link: mail.sent ? undefined : link, error: mail.error },
    { headers: { "Cache-Control": "no-store" } },
  );
}
