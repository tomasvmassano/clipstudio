import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import { backoff, hex, mimeOf, retryable, type MediaKind, type MediaStatus } from "@/lib/media-format";

/*
 * Biblioteca de media (W8, ADR-0038). Leituras e metadados por RPC; envio, links assinados e eliminação definitiva pelas
 * rotas /api/media (o servidor fala com o armazenamento através de src/lib/storage). O servidor decide tudo.
 */

type RpcError = Error & { code?: string };
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as RpcError;
    e.code = error.code;
    throw e;
  }
  return data as T;
}
async function api<T>(url: string, init?: RequestInit): Promise<T> {
  let r: Response;
  try {
    r = await fetch(url, { ...init, headers: { "content-type": "application/json", ...(init?.headers ?? {}) }, cache: "no-store" });
  } catch {
    const e = new Error("Sem ligação ao servidor. Verifica a rede e tenta de novo.") as RpcError;
    e.code = "rede";
    throw e;
  }
  const b = (await r.json().catch(() => ({}))) as { error?: string; code?: string };
  if (!r.ok) {
    const e = new Error(b.error || `Erro ${r.status}`) as RpcError;
    e.code = b.code;
    throw e;
  }
  return b as T;
}
export const errCode = (e: unknown) => (e as RpcError | null)?.code;

export type MediaVersion = {
  id: string; version_no: number; source: "upload" | "link"; state: "pendente" | "pronta" | "falhou" | "apagada";
  original_name: string | null; size_bytes: number | null; mime: string | null; sha256: string | null; checksum_verified: boolean;
  external_url: string | null; upload_expires_at: string | null; completed_at: string | null; failed_reason: string | null;
  deleted_at: string | null; created_at: string; uploaded_label: string | null; mine: boolean; expired: boolean;
};
export type MediaAsset = {
  id: string; kind: MediaKind; title: string; tags: string[]; format: string | null; status: MediaStatus; notes: string | null;
  project: { id: string; name: string } | null; content: { id: string; label: string } | null; take_id: string | null; publication_id: string | null;
  lifecycle: "ativo" | "no_lixo" | "eliminado"; trashed_at: string | null; trashed_label: string | null; trash_reason: string | null; purge_after: string | null;
  created_at: string; created_label: string | null; updated_at: string; lock_version: number;
  current: MediaVersion | null; pending: MediaVersion | null; versions: number;
};
export type MediaShare = {
  id: string; version_id: string; version_no: number; expires_at: string; note: string | null; open_count: number; last_opened_at: string | null;
  created_label: string | null; created_at: string; revoked_at: string | null; active: boolean;
};
export type Option = { id: string; label: string };
export type MediaAssetDetail = MediaAsset & {
  history: MediaVersion[]; shares: MediaShare[] | null; options: { contents: Option[]; takes: Option[]; publications: Option[] };
};
export type MediaPolicy = {
  allowed_mime: string[]; max_file_bytes: number; ceiling_bytes: number; quota_bytes: number; trash_days: number; pending_hours: number;
  customized: boolean; updated_at: string | null; updated_label: string | null;
};
export type MediaUsage = { stored_bytes: number; active_bytes: number; trash_bytes: number; orphan_bytes: number; pending_bytes: number; reserved_bytes: number; objects: number };
export type Orphan = MediaVersion & { asset_id: string; asset_title: string; asset_kind: MediaKind; object_exists: boolean };
export type MediaView = "ativos" | "lixo" | "orfaos";
export type MediaFilters = { view?: MediaView; q?: string; kind?: string; status?: string; format?: string; project_id?: string; tag?: string; limit?: number; offset?: number };
export type MediaLibrary = {
  workspace: string; timezone: string; view: MediaView;
  can: { read: boolean; upload: boolean; download: boolean; share: boolean; manage: boolean; policy: boolean };
  policy: MediaPolicy; usage: MediaUsage;
  antivirus: { available: boolean; reason: string }; cost: { available: boolean; reason: string };
  projects: { id: string; name: string }[]; tags: string[];
  counts: { ativos: number; lixo: number; orfaos: number | null };
  total: number; limit: number; offset: number; assets: MediaAsset[]; orphans: Orphan[];
};

const clean = (f: MediaFilters) => Object.fromEntries(Object.entries(f).filter(([, v]) => v !== undefined && v !== ""));
export const fetchLibrary = (a: Access, f: MediaFilters) => rpc<MediaLibrary>("media_library", { p_ws: a.ws, p_filters: clean(f), p_token: a.token });
export const fetchAsset = (a: Access, id: string) => rpc<MediaAssetDetail>("media_asset", { p_ws: a.ws, p_id: id, p_token: a.token });
export type AssetFields = Partial<{ title: string; tags: string[]; project_id: string | null; format: string | null; status: MediaStatus;
  content_id: string | null; take_id: string | null; publication_id: string | null; notes: string | null }>;
export const saveAsset = (a: Access, id: string, fields: AssetFields, lock?: number) =>
  rpc<MediaAsset>("media_asset_save", { p_ws: a.ws, p_id: id, p_fields: fields, p_lock: lock ?? null, p_token: a.token });
export const addLink = (a: Access, assetId: string | null, fields: AssetFields & { url: string }) =>
  rpc<MediaAsset>("media_link_add", { p_ws: a.ws, p_asset_id: assetId, p_fields: fields, p_token: a.token });
export const trashAsset = (a: Access, id: string, reason: string) => rpc<MediaAsset>("media_trash", { p_ws: a.ws, p_id: id, p_reason: reason, p_token: a.token });
export const restoreAsset = (a: Access, id: string) => rpc<MediaAsset>("media_restore", { p_ws: a.ws, p_id: id, p_token: a.token });
export const abandonUpload = (a: Access, versionId: string, reason: string) =>
  rpc<MediaVersion>("media_upload_abandon", { p_ws: a.ws, p_version: versionId, p_reason: reason, p_token: a.token });
export const savePolicy = (a: Access, fields: Partial<Pick<MediaPolicy, "allowed_mime" | "max_file_bytes" | "quota_bytes" | "trash_days">> | Record<string, null>) =>
  rpc<MediaPolicy>("media_policy_save", { p_ws: a.ws, p_fields: fields, p_token: a.token });
export const createShare = (a: Access, versionId: string, hours: number, note: string) =>
  rpc<{ id: string; token: string; expires_at: string; version_no: number }>("media_share_create", { p_ws: a.ws, p_version: versionId, p_hours: hours, p_note: note, p_token: a.token });
export const revokeShare = (a: Access, id: string) => rpc<{ id: string }>("media_share_revoke", { p_ws: a.ws, p_id: id, p_token: a.token });
export const shareUrl = (token: string) => `${window.location.origin}/api/media/share/${token}`;

/** URL assinado curto (pré-visualizar 5 min, descarregar 2 min). */
export const signedUrl = (a: Access, versionId: string, purpose: "preview" | "download") =>
  api<{ url: string; mime: string; filename: string; expires_at: string }>(`/api/media/versions/${versionId}/url?ws=${encodeURIComponent(a.ws)}&purpose=${purpose}`);

export const purge = (a: Access, scope: "orfaos" | "lixo", ids: string[], confirm: string) =>
  api<{ versions_deleted: number; assets_purged: number; remaining: string[]; storage_error: string | null }>("/api/media/purge",
    { method: "POST", body: JSON.stringify({ ws: a.ws, scope, ids, confirm }) });

// ---------- envio com progresso e retentativa ----------
export type UploadTarget = { url: string; method: "PUT"; headers: Record<string, string>; expires_in_seconds: number };
export type UploadPhase = "checksum" | "a_registar" | "a_enviar" | "a_esperar" | "a_confirmar" | "pronta" | "falhou" | "cancelado";
export type UploadProgress = { phase: UploadPhase; loaded: number; total: number; attempt: number; message?: string; versionId?: string; assetId?: string };

/** SHA-256 no browser (Web Crypto). Lê o ficheiro inteiro para memória: serve até ao teto atual (50 MiB por defeito). */
export async function sha256File(file: Blob): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", await file.arrayBuffer()));
}

class PutError extends Error { constructor(readonly status: number, message: string) { super(message); } }

function put(target: UploadTarget, file: Blob, onProgress: (loaded: number) => void, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open(target.method, target.url);
    for (const [k, v] of Object.entries(target.headers)) xhr.setRequestHeader(k, v);
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress(e.loaded); };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else {
        let msg = `Erro ${xhr.status}`;
        try { const b = JSON.parse(xhr.responseText) as { message?: string; error?: string }; msg = b.message || b.error || msg; } catch { /* resposta sem JSON: fica o código */ }
        reject(new PutError(xhr.status, msg));
      }
    };
    xhr.onerror = () => reject(new PutError(0, "Falha de rede durante o envio."));
    xhr.ontimeout = () => reject(new PutError(408, "O envio demorou demasiado."));
    if (signal) {
      if (signal.aborted) { reject(new DOMException("cancelado", "AbortError")); return; }
      signal.addEventListener("abort", () => { xhr.abort(); reject(new DOMException("cancelado", "AbortError")); }, { once: true });
    }
    xhr.send(file);
  });
}

const sleep = (ms: number, signal?: AbortSignal) => new Promise<void>((res, rej) => {
  const t = setTimeout(res, ms);
  signal?.addEventListener("abort", () => { clearTimeout(t); rej(new DOMException("cancelado", "AbortError")); }, { once: true });
});

/** O objeto já existe (uma tentativa anterior chegou, a resposta perdeu-se): segue para confirmar. */
const alreadyThere = (e: PutError) => e.status === 409 || (e.status === 400 && /exist|duplicate/i.test(e.message));

async function sendWithRetry(a: Access, versionId: string, first: UploadTarget | null, file: Blob,
  report: (p: Partial<UploadProgress>) => void, signal?: AbortSignal, maxAttempts = 4) {
  let target = first;
  for (let attempt = 1; ; attempt++) {
    try {
      if (!target) {
        const t = await api<{ upload: UploadTarget | null }>(`/api/media/uploads/${versionId}/target`, { method: "POST", body: JSON.stringify({ ws: a.ws }), signal });
        if (!t.upload) return;                                     // o objeto já lá está
        target = t.upload;
      }
      report({ phase: "a_enviar", attempt, loaded: 0 });
      await put(target, file, (loaded) => report({ loaded }), signal);
      return;
    } catch (e) {
      if ((e as Error).name === "AbortError") throw e;
      if (e instanceof PutError && alreadyThere(e)) return;
      const status = e instanceof PutError ? e.status : errCode(e) === "rede" ? 0 : -1;
      if (attempt >= maxAttempts || !(retryable(status) || status === 401 || status === 403)) throw e;
      // URL assinado expirado (401/403) ou falha passageira: pede um alvo novo e tenta outra vez
      target = null;
      const wait = backoff(attempt);
      report({ phase: "a_esperar", attempt, message: `${(e as Error).message} Nova tentativa em ${Math.round(wait / 1000)} s.` });
      await sleep(wait, signal);
    }
  }
}

async function complete(a: Access, versionId: string, signal?: AbortSignal) {
  return api<{ state: "pronta" | "falhou"; reason?: string; asset?: MediaAsset }>(`/api/media/uploads/${versionId}/complete`,
    { method: "POST", body: JSON.stringify({ ws: a.ws }), signal });
}

/** Carrega um ficheiro (ativo novo ou versão nova de assetId). Progresso real do XHR; repete falhas passageiras. */
export async function uploadFile(a: Access, file: File, opts: { assetId?: string | null; fields?: AssetFields & { kind?: MediaKind } },
  onProgress: (p: UploadProgress) => void, signal?: AbortSignal): Promise<{ assetId: string; versionId: string }> {
  let state: UploadProgress = { phase: "checksum", loaded: 0, total: file.size, attempt: 0 };
  const report = (p: Partial<UploadProgress>) => { state = { ...state, ...p }; onProgress(state); };
  report({});
  const sha256 = await sha256File(file);
  if (signal?.aborted) throw new DOMException("cancelado", "AbortError");
  report({ phase: "a_registar" });
  const reg = await api<{ asset_id: string; version_id: string; upload: UploadTarget }>("/api/media/uploads", {
    method: "POST", signal,
    body: JSON.stringify({ ws: a.ws, asset_id: opts.assetId ?? null, fields: opts.assetId ? {} : (opts.fields ?? {}),
      file: { name: file.name, size: file.size, mime: mimeOf(file.name, file.type), sha256 } }),
  });
  report({ versionId: reg.version_id, assetId: reg.asset_id });
  await sendWithRetry(a, reg.version_id, reg.upload, file, report, signal);
  return finish(a, reg.version_id, reg.asset_id, report, signal);
}

/** Retoma um upload pendente com o mesmo ficheiro (o servidor confere tamanho e SHA-256 no fim). */
export async function resumeUpload(a: Access, versionId: string, assetId: string, file: File,
  onProgress: (p: UploadProgress) => void, signal?: AbortSignal) {
  let state: UploadProgress = { phase: "a_registar", loaded: 0, total: file.size, attempt: 0, versionId, assetId };
  const report = (p: Partial<UploadProgress>) => { state = { ...state, ...p }; onProgress(state); };
  report({});
  await sendWithRetry(a, versionId, null, file, report, signal);
  return finish(a, versionId, assetId, report, signal);
}

async function finish(a: Access, versionId: string, assetId: string, report: (p: Partial<UploadProgress>) => void, signal?: AbortSignal) {
  report({ phase: "a_confirmar" });
  for (let attempt = 1; ; attempt++) {
    try {
      const r = await complete(a, versionId, signal);
      if (r.state !== "pronta") {
        report({ phase: "falhou", message: `O servidor recusou o ficheiro (${r.reason ?? "sem motivo"}). Carrega outra vez.` });
        throw Object.assign(new Error(r.reason ?? "falhou"), { code: "recusado" });
      }
      report({ phase: "pronta" });
      return { assetId, versionId };
    } catch (e) {
      if ((e as Error).name === "AbortError" || errCode(e) === "recusado" || attempt >= 3 || errCode(e) !== "rede") throw e;
      await sleep(backoff(attempt), signal);
    }
  }
}
