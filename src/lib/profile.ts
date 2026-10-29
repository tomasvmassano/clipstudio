import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/** Perfil da própria pessoa (W1-15, FR-14-01). O servidor valida cada campo. */
export type ProfilePatch = Partial<{ display_name: string | null; avatar_path: string | null; timezone: string | null; theme: "system" | "light" | "dark"; preferred_workspace: string | null }>;

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const updateProfile = (patch: ProfilePatch) => rpc<Record<string, unknown>>("profile_update", { p_patch: patch });
export const securityLog = () => rpc<{ at: string; action: string }[]>("my_security_log", { p_limit: 30 });
export const securityEvent = (action: "security.password_changed" | "security.mfa_enabled" | "security.mfa_disabled" | "security.signed_out_everywhere") =>
  rpc<void>("security_event", { p_action: action }).catch(() => undefined); // o histórico nunca impede a ação

export const AVATAR_TYPES = ["image/png", "image/jpeg", "image/webp"];
export const AVATAR_MAX = 1024 * 1024;

/** Sobe o avatar para a pasta da própria pessoa (RLS do storage) e grava o caminho no perfil. */
export async function uploadAvatar(uid: string, file: File): Promise<string> {
  if (!AVATAR_TYPES.includes(file.type)) throw new Error("Usa uma imagem PNG, JPG ou WebP.");
  if (file.size > AVATAR_MAX) throw new Error("A imagem tem de ter até 1 MB.");
  const ext = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
  const path = `${uid}/avatar-${Date.now()}.${ext}`;
  const { error } = await supabase().storage.from("avatars").upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error("Não foi possível guardar a imagem. Tenta outra vez.");
  await updateProfile({ avatar_path: path });
  return path;
}

/** URL temporário do avatar (bucket privado). */
export async function avatarUrl(path: string | null | undefined): Promise<string | null> {
  if (!path) return null;
  const { data } = await supabase().storage.from("avatars").createSignedUrl(path, 3600);
  return data?.signedUrl ?? null;
}

export const SECURITY_LABEL: Record<string, string> = {
  "profile.updated": "Perfil alterado",
  "security.password_changed": "Palavra-passe mudada",
  "security.mfa_enabled": "Verificação em dois passos ligada",
  "security.mfa_disabled": "Verificação em dois passos desligada",
  "security.signed_out_everywhere": "Sessão terminada em todos os dispositivos",
  "invitation.accepted": "Convite aceite",
};
