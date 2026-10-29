import assert from "node:assert/strict";
import { inviteMessage, sendInviteEmail } from "../src/lib/server/invite-email.ts";

let n = 0;
const inv = { token: "a".repeat(48), email: "nova@exemplo.pt", kind: "workspace" as const, target: "Numeiro <b>", role: "contributor",
  inviter: "tomas@exemplo.pt", expires_at: "2026-11-12T10:00:00Z" };
const m = inviteMessage(inv, "https://app.exemplo/convite?t=" + inv.token);
assert.ok(m.subject.includes("tomas@exemplo.pt convidou-te para Numeiro")); n++;
assert.ok(m.text.includes("como colaborador") && m.text.includes("nova@exemplo.pt") && m.text.includes("12 de novembro")); n++;
assert.ok(m.html.includes("Numeiro &lt;b&gt;") && !m.html.includes("Numeiro <b>")); n++;   // nomes escapados no HTML
assert.ok(!m.text.includes("—") && !m.html.includes("—")); n++;                            // sem travessões
const ag = inviteMessage({ ...inv, kind: "agency", target: "ClipStudio", role: "agency_member" }, "x");
assert.ok(ag.text.includes("a equipa da agência ClipStudio") && ag.text.includes("membro da agência")); n++;
delete process.env.RESEND_API_KEY; delete process.env.INVITE_FROM;
assert.deepEqual(await sendInviteEmail(inv, "x"), { sent: false }); n++;                     // sem chave: não envia, a app mostra o link
console.log(`invite-email ${n}/${n}`);
