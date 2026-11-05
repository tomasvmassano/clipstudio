import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/** Frases-persona do cliente (R-17, CHG-003, ADR-0053): hipérbole sobre o próprio criador, só desta lista aprovada.
 *  Cada gravação é uma versão nova (imutável); quem envolve outra pessoa leva o consentimento dela. O servidor decide tudo. */
export type PersonaInvolves = { name: string; consent_by: string; consent_at: string; consent_note?: string };
export type PersonaPhrase = { id: string; text: string; involves?: PersonaInvolves | null };
export type PersonaList = {
  version: number; phrases: PersonaPhrase[]; note: string | null; saved_by: string | null; saved_at: string | null;
  history: { version: number; count: number; note: string | null; by: string | null; at: string }[];
  can: { manage: boolean };
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const fetchPersona = (a: Access) => rpc<PersonaList>("persona_list_get", { p_ws: a.ws, p_token: a.token });
export const fetchPersonaVersion = (a: Access, version: number) =>
  rpc<{ version: number; phrases: PersonaPhrase[]; note: string | null; by: string | null; at: string }>("persona_list_version", { p_ws: a.ws, p_version: version, p_token: a.token });
export const savePersona = (a: Access, phrases: PersonaPhrase[], expected: number, note?: string) =>
  rpc<PersonaList>("persona_list_save", { p_ws: a.ws, p_phrases: phrases, p_expected: expected, p_note: note?.trim() || null, p_token: a.token });

export { personaProblem, newPersonaId } from "@/lib/persona-rules";
