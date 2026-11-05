-- W10-06 · Verificador antes da revisão humana (PRD VAR-04, R-17; AGENTS §7). ADR-0054.
-- Aditiva (expandir): tabela nova fechada à API, uma função do worker e uma de leitura. Nada do que existe muda:
-- o motor antigo não chama worker_save_verification e a app antiga não lê a tabela.

create table if not exists public.script_verifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete cascade,
  version_id uuid references public.content_versions(id) on delete set null,   -- versão do texto que foi verificada
  job_id uuid references public.agent_jobs(id) on delete set null,
  marca text not null check (marca in ('ok','atencao','rever','juridico','bloqueado')),
  verifier_version text not null check (length(verifier_version) between 1 and 40),
  model text check (length(model) <= 80),
  prompts_version text check (length(prompts_version) <= 40),
  persona_version integer,
  result jsonb not null,
  created_at timestamptz not null default now(),
  unique (job_id, content_id)
);
create index if not exists script_verifications_content on public.script_verifications (workspace_id, content_id, created_at desc);
alter table public.script_verifications enable row level security;
revoke all on public.script_verifications from public, anon, authenticated;
-- sem políticas: só as funções abaixo leem e escrevem (security definer, com autorização própria)

-- Resultado do verificador para um guião que esta execução acabou de gravar. Idempotente por (execução, guião).
create or replace function public.worker_save_verification(p_job uuid, p_worker text, p_content text, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; g guioes; v script_verifications; h jsonb; a jsonb;
  flags text[] := array['ok','atencao','rever','juridico','bloqueado'];
  kinds text[] := array['persona','opiniao','facto','terceiro','validade'];
begin
  select * into j from agent_jobs where id = p_job;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  -- só guiões gravados por esta execução: o worker não escreve sobre guiões de outro cliente nem de outra execução
  if not exists (select 1 from agent_job_outputs where job_id = j.id and content_id = p_content and workspace_id = j.workspace_id) then
    raise exception 'guiao_fora_da_execucao' using errcode = '22023';
  end if;
  select * into v from script_verifications where job_id = j.id and content_id = p_content;
  if v.id is not null then return jsonb_build_object('id', v.id, 'created', false); end if;
  -- nunca confiar no payload: forma, marcas e tamanho
  if jsonb_typeof(p_result) <> 'object' or pg_column_size(p_result) > 65536 then raise exception 'verificacao_invalida' using errcode = '22023'; end if;
  if not (p_result->>'marca' = any (flags)) or btrim(coalesce(p_result->>'versao', '')) = ''
     or jsonb_typeof(p_result->'hooks') <> 'array' or jsonb_array_length(p_result->'hooks') > 10 then
    raise exception 'verificacao_invalida' using errcode = '22023';
  end if;
  for h in select * from jsonb_array_elements(p_result->'hooks') loop
    if jsonb_typeof(h) <> 'object' or not (h->>'marca' = any (flags)) or jsonb_typeof(coalesce(h->'afirmacoes', '[]')) <> 'array'
       or jsonb_array_length(coalesce(h->'afirmacoes', '[]')) > 20 then
      raise exception 'verificacao_invalida' using errcode = '22023';
    end if;
    for a in select * from jsonb_array_elements(coalesce(h->'afirmacoes', '[]')) loop
      if jsonb_typeof(a) <> 'object' or not (a->>'tipo' = any (kinds)) or not (a->>'marca' = any (flags)) then
        raise exception 'verificacao_invalida' using errcode = '22023';
      end if;
    end loop;
  end loop;
  select * into g from guioes where id = p_content;
  insert into script_verifications (workspace_id, content_id, version_id, job_id, marca, verifier_version, model, prompts_version, persona_version, result)
  values (j.workspace_id, g.id, g.current_version_id, j.id, p_result->>'marca', left(p_result->>'versao', 40), left(p_result->>'modelo', 80),
          left(p_result->>'prompts_version', 40),
          case when (p_result->>'persona_version') ~ '^\d{1,9}$' then (p_result->>'persona_version')::int end, p_result)
  returning * into v;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'script.verified', 'content', g.id,
          jsonb_build_object('verification_id', v.id, 'marca', v.marca, 'verifier_version', v.verifier_version, 'job_id', j.id));
  update agent_jobs set heartbeat_at = now() where id = j.id;
  return jsonb_build_object('id', v.id, 'created', true);
end $$;

-- Leitura para a revisão: o último resultado de cada guião pedido, só do cliente autorizado (scripts.read, sessão ou código).
-- O cliente no pedido não autoriza nada: é verificado aqui e filtra as linhas; guiões de outro cliente não aparecem.
create or replace function public.content_verifications(p_ws text, p_ids text[], p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_ids is null or cardinality(p_ids) > 200 then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  perform public._content_require('scripts.read', p_ws, p_token, 'script.verification_read', null);
  return coalesce((
    select jsonb_object_agg(x.content_id, jsonb_build_object('id', x.id, 'marca', x.marca, 'version_id', x.version_id,
             'verifier_version', x.verifier_version, 'model', x.model, 'prompts_version', x.prompts_version,
             'persona_version', x.persona_version, 'created_at', x.created_at, 'result', x.result))
      from (select distinct on (s.content_id) s.* from script_verifications s
             join guioes g on g.id = s.content_id and g.client_id = p_ws and g.deleted_at is null
            where s.workspace_id = p_ws and s.content_id = any (p_ids)
            order by s.content_id, s.created_at desc) x), '{}'::jsonb);
end $$;

revoke all on function public.worker_save_verification(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.worker_save_verification(uuid, text, text, jsonb) to service_role, engine_worker;
revoke all on function public.content_verifications(text, text[], text) from public;
grant execute on function public.content_verifications(text, text[], text) to anon, authenticated;

/* Rollback (compatível, a app e o motor anteriores não dependem de nada disto):
   drop function if exists public.content_verifications(text, text[], text);
   drop function if exists public.worker_save_verification(uuid, text, text, jsonb);
   drop table if exists public.script_verifications;   -- perde os resultados guardados (o agent_log do motor mantém cada chamada)
   delete from domain_events where type = 'script.verified'; (opcional) */
