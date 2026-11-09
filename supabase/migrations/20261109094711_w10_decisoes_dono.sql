-- W10-22 · Decisões do dono de 2026-11-09 (ADR-0071). Só aditivo (expand): reescreve 4 funções a partir da definição
-- atual no main e acrescenta 1 função de trigger e 1 trigger. Nenhuma tabela, coluna, capacidade ou grant muda.
--  1. FR-10-01 / AGENTS §9: a equipa do próprio cliente (workspace_access.affiliation_type = 'client_staff') nunca vê custos
--     de IA, seja qual for o papel ou a exceção individual. _authorize_base recusa qualquer capacidade costs.* nesse acesso,
--     por isso todas as RPCs de custos (costs_ai_usage, costs_ai_usage_export, content_costs, content_costs_export), o
--     widget kpi.costs, a coluna de custo da configuração dos agentes e o menu (my_context.capabilities) recusam ou escondem,
--     com o mesmo 42501 auditado (audit_denied) de _content_require. Staff da agência com costs.read continua a ver; o
--     código de equipa já nunca via. _access_explain diz porquê na consola de permissões.
--     Base: _authorize_base de 20261103203930_w1_preview_papel.sql; _access_explain de 20261029105036_w1_permissions_console.sql.
--  2. EDL-07 / EDL-11: pôr a etiqueta ia-imagem, ia-atencao ou ia-musica num ativo da Biblioteca é a declaração de quem o
--     faz de que o cliente tem direitos para a IA usar o ficheiro. media_asset_save aceita p_fields.ai_rights_confirmed; um
--     trigger em media_assets recusa (22023 direitos_ia_por_confirmar) um pedido de uma pessoa ou do código de equipa que
--     acrescente uma dessas etiquetas sem a confirmação, e regista no histórico 'media.ai_rights_declared' (quem, quando,
--     etiquetas, ativo, versão atual). Envio (media_upload_begin) e links (media_link_add) não mudam: sem confirmação,
--     acrescentar ia-* por aí é recusado e a etiqueta põe-se na ficha do ativo. Workers e service role não são travados
--     (não acrescentam ia-*), mas ficam registados se o fizerem.
--     Base: media_asset_save de 20261103152523_w8_media_p2.sql.
--  3. LRN-04: a equipa do cliente com learn.read vê as lições da agência em vigor, só leitura (categoria e texto, sem
--     evidência nem quem mudou); as propostas da agência continuam só para a equipa da agência.
--     Base: lrn_lessons_list de 20261106132216_w10_aprendizagem.sql.
-- Rollback no fim.

-- ───────────── 1. custos fora do alcance da equipa do cliente ─────────────
create or replace function public._authorize_base(p_cap text, p_ws text default null, p_uid uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_role text; v_org uuid; v_aff text;
begin
  if p_uid is null then return false; end if;
  if not public._mfa_ok(p_uid) then return false; end if;                                  -- MFA ativo exige aal2 (W1-15)
  if not exists (select 1 from capabilities where key = p_cap) then return false; end if;   -- desconhecida = negado
  if p_ws is null then
    return exists (select 1 from agency_memberships m join role_capabilities rc on rc.scope = 'org' and rc.role = m.agency_role and rc.capability = p_cap
                   where m.user_id = p_uid and m.status = 'active');
  end if;
  select organization_id into v_org from clients where id = p_ws and status = 'active';
  if v_org is null then return false; end if;
  -- negação explícita prevalece (CAP-03)
  if exists (select 1 from permission_grants g where g.user_id = p_uid and g.workspace_id = p_ws and g.capability = p_cap
             and g.effect = 'deny' and g.revoked_at is null and (g.expires_at is null or g.expires_at > now())) then return false; end if;
  -- agency owner: acesso global à sua organização (auditado nas escritas)
  if exists (select 1 from agency_memberships m where m.user_id = p_uid and m.organization_id = v_org
             and m.agency_role = 'agency_owner' and m.status = 'active') then return true; end if;
  select a.workspace_role, a.affiliation_type into v_role, v_aff from workspace_access a
   where a.user_id = p_uid and a.workspace_id = p_ws and a.status = 'active' and (a.expires_at is null or a.expires_at > now());
  if v_role is null then return false; end if;
  -- staff da agência suspenso na organização perde acesso aos clientes
  if exists (select 1 from workspace_access a join agency_memberships m on m.user_id = a.user_id and m.organization_id = v_org
             where a.user_id = p_uid and a.workspace_id = p_ws and a.affiliation_type = 'agency_staff' and m.status <> 'active') then return false; end if;
  -- custos de IA nunca para a equipa do próprio cliente, nem com papel nem com exceção (decisão do dono 2026-11-09, ADR-0071)
  if v_aff = 'client_staff' and p_cap like 'costs.%' then return false; end if;
  return exists (select 1 from role_capabilities where scope = 'ws' and role = v_role and capability = p_cap)
      or exists (select 1 from permission_grants g where g.user_id = p_uid and g.workspace_id = p_ws and g.capability = p_cap
                 and g.effect = 'allow' and g.revoked_at is null and (g.expires_at is null or g.expires_at > now()));
end $$;

create or replace function public._access_explain(p_ws text, p_user uuid, p_cap text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clients; a workspace_access; g record; m agency_memberships; cap capabilities; reasons jsonb := '[]';
begin
  select * into cap from capabilities where key = p_cap;
  if cap.key is null then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Capacidade desconhecida: negado por defeito.')); end if;
  select * into c from clients where id = p_ws;
  if c.id is null or c.status <> 'active' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O cliente está arquivado ou não existe.')); end if;
  select * into g from permission_grants where user_id = p_user and workspace_id = p_ws and capability = p_cap and effect = 'deny'
     and revoked_at is null and (expires_at is null or expires_at > now()) order by created_at desc limit 1;
  if g.id is not null then
    return jsonb_build_object('allowed', false, 'source', 'deny', 'grant_id', g.id, 'reasons', jsonb_build_array(
      'Negação explícita' || coalesce(' até ' || to_char(g.expires_at at time zone c.timezone, 'DD/MM/YYYY HH24:MI'), '') || coalesce(': ' || g.reason, '') || '. Prevalece sobre o papel.'));
  end if;
  select * into m from agency_memberships where user_id = p_user and organization_id = c.organization_id;
  if m.user_id is not null and m.agency_role = 'agency_owner' and m.status = 'active' then
    return jsonb_build_object('allowed', true, 'source', 'agency_owner', 'reasons', jsonb_build_array('Dono da agência: acesso a todos os clientes da agência (auditado).'));
  end if;
  select * into a from workspace_access where workspace_id = p_ws and user_id = p_user;
  if a.user_id is null or a.status = 'removed' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Não tem acesso a este cliente.')); end if;
  if a.status = 'suspended' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O acesso está suspenso.')); end if;
  if a.expires_at is not null and a.expires_at <= now() then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O acesso expirou.')); end if;
  if a.affiliation_type = 'agency_staff' and m.status is distinct from 'active' then
    return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Está suspenso na agência, por isso perde os clientes.'));
  end if;
  if a.affiliation_type = 'client_staff' and p_cap like 'costs.%' then
    return jsonb_build_object('allowed', false, 'source', 'policy', 'reasons', jsonb_build_array(
      'A equipa do cliente nunca vê custos de IA, seja qual for o papel ou a exceção (decisão do dono, ADR-0071).'));
  end if;
  if exists (select 1 from role_capabilities where scope = 'ws' and role = a.workspace_role and capability = p_cap) then
    reasons := reasons || jsonb_build_array(format('O papel %s inclui esta capacidade.', a.workspace_role));
  end if;
  select * into g from permission_grants where user_id = p_user and workspace_id = p_ws and capability = p_cap and effect = 'allow'
     and revoked_at is null and (expires_at is null or expires_at > now()) order by created_at desc limit 1;
  if g.id is not null then
    reasons := reasons || jsonb_build_array('Exceção dada à pessoa' || coalesce(' até ' || to_char(g.expires_at at time zone c.timezone, 'DD/MM/YYYY HH24:MI'), '') || coalesce(': ' || g.reason, '') || '.');
  end if;
  if jsonb_array_length(reasons) = 0 then
    return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array(format('O papel %s não inclui esta capacidade e não há exceção.', a.workspace_role)));
  end if;
  return jsonb_build_object('allowed', true, 'source', case when g.id is not null and not exists (select 1 from role_capabilities where scope = 'ws' and role = a.workspace_role and capability = p_cap) then 'grant' else 'role' end,
                            'grant_id', g.id, 'reasons', reasons);
end $$;

-- ───────────── 2. declaração de direitos ao etiquetar para a IA ─────────────
create or replace function public._media_ai_tags() returns text[] language sql immutable as $$ select array['ia-imagem', 'ia-atencao', 'ia-musica'] $$;

-- Etiquetas ia-* novas num ativo: pedido de uma pessoa ou do código de equipa sem confirmação → recusa; senão regista.
create or replace function public.media_assets_ai_rights() returns trigger
language plpgsql security definer set search_path = public as $$
declare added text[]; req text := coalesce(auth.role(), ''); confirmed boolean := current_setting('clipstudio.ai_rights_confirmed', true) = 'on';
        v media_versions;
begin
  select coalesce(array_agg(t order by t), '{}') into added from unnest(new.tags) t
   where t = any (public._media_ai_tags()) and (tg_op = 'INSERT' or not t = any (coalesce(old.tags, '{}')));
  if cardinality(added) = 0 then return null; end if;
  if req in ('authenticated', 'anon') and not confirmed then
    raise exception 'direitos_ia_por_confirmar' using errcode = '22023',
      detail = 'As etiquetas ia-imagem, ia-atencao e ia-musica deixam a IA usar o ficheiro. Põe-nas na ficha do ativo e confirma que o cliente tem direitos para isso.';
  end if;
  select * into v from media_versions where id = new.current_version_id;
  perform public._media_audit(new.workspace_id, 'media.ai_rights_declared', 'media_asset', new.id::text, null,
    jsonb_build_object('tags', added, 'asset_id', new.id, 'title', new.title, 'kind', new.kind,
                       'version_id', v.id, 'version_no', v.version_no, 'confirmed', confirmed, 'request_role', nullif(req, ''),
                       'declaration', 'Confirmo que o cliente tem direitos para a IA usar este ficheiro.'));
  return null;
end $$;
drop trigger if exists media_assets_ai_rights on public.media_assets;
create trigger media_assets_ai_rights after insert or update of tags on public.media_assets
  for each row execute function public.media_assets_ai_rights();

create or replace function public.media_asset_save(p_ws text, p_id uuid, p_fields jsonb, p_lock int default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets; b media_assets; f jsonb := coalesce(p_fields, '{}') - 'ai_rights_confirmed';
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.asset_save', p_id::text);
  perform public._media_uid();
  select * into a from media_assets where id = p_id and workspace_id = p_ws for update;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023', detail = 'Recupera o ativo do lixo antes de o editar.'; end if;
  if p_lock is not null and p_lock <> a.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  if f = '{}' then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  b := a;
  a := public._media_apply_fields(a, f, array['title', 'tags', 'project_id', 'format', 'status', 'content_id', 'take_id', 'publication_id', 'notes']);
  -- a confirmação só vale para esta escrita (o trigger media_assets_ai_rights lê-a)
  perform set_config('clipstudio.ai_rights_confirmed', case when (p_fields->>'ai_rights_confirmed') = 'true' then 'on' else 'off' end, true);
  update media_assets set title = a.title, tags = a.tags, project_id = a.project_id, format = a.format, status = a.status, content_id = a.content_id,
         take_id = a.take_id, publication_id = a.publication_id, notes = a.notes
   where id = p_id returning * into a;
  perform set_config('clipstudio.ai_rights_confirmed', 'off', true);
  perform public._media_audit(p_ws, 'media.asset_updated', 'media_asset', p_id::text,
    to_jsonb(b) - array['updated_at', 'lock_version'], to_jsonb(a) - array['updated_at', 'lock_version']);
  return public._media_asset_json(a);
end $$;

revoke all on function public._media_ai_tags(), public.media_assets_ai_rights() from public, anon, authenticated;

-- ───────────── 3. lições da agência em vigor, só leitura, para a equipa do cliente ─────────────
create or replace function public.lrn_lessons_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid; staff boolean; agency boolean; cv lrn_lesson_versions; av lrn_lesson_versions; last_job agent_jobs; since timestamptz;
begin
  perform public._content_require('learn.read', p_ws, p_token, 'lrn.lessons_list', p_ws);
  perform public._lrn_require_flag('learn.lessons', p_ws, p_token);
  select organization_id into org from clients where id = p_ws;
  staff := public._lrn_is_agency_staff(org);
  agency := staff and public._org_can('learn.lessons.agency', org);
  cv := public._lrn_active('client', org, p_ws);
  av := public._lrn_active('agency', org, null);
  select * into last_job from agent_jobs where workspace_id = p_ws and kind = 'lesson_editor' order by created_at desc limit 1;
  since := coalesce((select max((j.params->>'until')::timestamptz) from agent_jobs j where j.workspace_id = p_ws and j.kind = 'lesson_editor' and j.status = 'succeeded'),
                    now() - interval '7 days');
  return jsonb_build_object(
    'can', jsonb_build_object('approve', public.ws_can('learn.lessons.approve', p_ws, p_token), 'agency', agency),
    'proposed', (select coalesce(jsonb_agg(public._lrn_lesson_json(l, true) order by l.proposed_at desc), '[]') from lrn_lessons l
                  where l.level = 'client' and l.workspace_id = p_ws and l.status = 'proposed'),
    'decided', (select coalesce(jsonb_agg(public._lrn_lesson_json(l, true) order by l.decided_at desc), '[]') from
                  (select * from lrn_lessons where level = 'client' and workspace_id = p_ws and status <> 'proposed' order by decided_at desc limit 100) l),
    'active', public._lrn_version_json(cv),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'active', v.active, 'n', jsonb_array_length(v.lessons),
                    'change', v.change, 'created_label', v.created_label, 'created_at', v.created_at) order by v.version_no desc), '[]')
                  from (select * from lrn_lesson_versions where level = 'client' and organization_id = org and workspace_id = p_ws order by version_no desc limit 50) v),
    'signals', (select jsonb_build_object('since', since,
                    'edits', count(*) filter (where kind in ('edit', 'approved')),
                    'no_reason', count(*) filter (where kind in ('approved', 'changes_requested', 'rejected') and cardinality(codes) = 0 and note is null),
                    'unedited', count(*) filter (where kind = 'approved_unedited'),
                    'rejected', count(*) filter (where kind in ('changes_requested', 'rejected')))
                  from lrn_edit_signals where workspace_id = p_ws and created_at >= since),
    'job', public._reference_job_json(last_job),
    -- equipa da agência: regras em vigor e propostas (estas só com learn.lessons.agency). Só regras, sem dados de outro cliente (LRN-04).
    -- equipa do cliente (sessão individual): só as regras da agência em vigor, só leitura, categoria e texto (decisão 2026-11-09, ADR-0071).
    -- código de equipa: nada da agência.
    'agency', case
       when staff then jsonb_build_object(
         'readonly', false,
         'active', public._lrn_version_json(av),
         'proposed', case when agency then (select coalesce(jsonb_agg(public._lrn_lesson_json(l, false) order by l.proposed_at desc), '[]')
                      from lrn_lessons l where l.level = 'agency' and l.organization_id = org and l.status = 'proposed') else '[]'::jsonb end)
       when auth.uid() is not null then jsonb_build_object(
         'readonly', true,
         'active', case when av.id is null then null else jsonb_build_object('id', av.id, 'version_no', av.version_no, 'active', true,
                     'lessons', (select coalesce(jsonb_agg(jsonb_build_object('id', x->>'id', 'category', x->>'category', 'text', x->>'text') order by o), '[]')
                                   from jsonb_array_elements(coalesce(av.lessons, '[]'::jsonb)) with ordinality e(x, o))) end,
         'proposed', '[]'::jsonb)
       else null end);
end $$;
-- (grants de lrn_lessons_list mantêm-se: create or replace não os altera)

/* Rollback (compatível: nenhuma assinatura mudou):
   1. recriar public._authorize_base com o corpo de 20261103203930_w1_preview_papel.sql e public._access_explain com o corpo
      de 20261029105036_w1_permissions_console.sql (a equipa do cliente volta a ver custos pelos papéis dono/admin).
   2. drop trigger if exists media_assets_ai_rights on public.media_assets;
      drop function if exists public.media_assets_ai_rights(), public._media_ai_tags();
      recriar public.media_asset_save com o corpo de 20261103152523_w8_media_p2.sql (o browser deixa de mandar
      ai_rights_confirmed antes do rollback, ou a versão antiga recusa com campo_desconhecido).
      os registos 'media.ai_rights_declared' no histórico ficam (append-only).
   3. recriar public.lrn_lessons_list com o corpo de 20261106132216_w10_aprendizagem.sql. */
