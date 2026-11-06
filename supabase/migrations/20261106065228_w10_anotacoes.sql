-- W10-15 · Anotações desenhadas no vídeo (PRD FR-05-03, OPS-07, QA-07; ADR-0067). Expand (aditivo).
-- Quem revê um vídeo guardado (player da app) pausa, desenha no fotograma (caneta, seta, retângulo, círculo) e o desenho fica
-- preso ao comentário nesse momento. O desenho é guardado como vetores normalizados (0..1 em relação ao fotograma do vídeo), por
-- isso escala em qualquer ecrã. Validado aqui (tipos, cores, número de formas e de pontos, intervalos numéricos) e reescrito na
-- forma canónica: só as chaves conhecidas ficam guardadas. Vídeos da Drive continuam sem desenho (o player da Drive não dá o
-- fotograma nem o tempo). media_review_comment ganha p_annotation opcional no fim: as chamadas antigas (por nome ou por posição,
-- 3 a 6 argumentos) continuam a funcionar sem mudar nada. Rollback no fim.

alter table public.media_comments add column if not exists annotation jsonb;
alter table public.media_comments drop constraint if exists media_comments_annotation_check;
alter table public.media_comments add constraint media_comments_annotation_check
  check (annotation is null or (jsonb_typeof(annotation) = 'object' and pg_column_size(annotation) <= 131072));

-- Limites (iguais a src/lib/annotation.ts): 50 formas, 500 pontos por traço, 2000 pontos ao todo, coordenadas 0..1,
-- espessura 0.002..0.05 da largura do fotograma, cor #rrggbb. Devolve a anotação canónica (coordenadas a 4 casas) ou erro 22023.
create or replace function public._review_annotation(p jsonb) returns jsonb
language plpgsql immutable set search_path = public as $$
declare s jsonb; pt jsonb; pts jsonb; out_shapes jsonb := '[]'; out_pts jsonb; total int := 0; n int; ty text; w numeric; x numeric; y numeric;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if pg_column_size(p) > 262144 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Desenho grande demais.'; end if;
  if coalesce(jsonb_typeof(p), '') <> 'object' or coalesce(p->'v' <> '1'::jsonb, true) or coalesce(jsonb_typeof(p->'shapes'), '') <> 'array' then
    raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Formato desconhecido.'; end if;
  n := jsonb_array_length(p->'shapes');
  if n = 0 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Desenho vazio.'; end if;
  if n > 50 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Máximo de 50 formas.'; end if;
  for s in select value from jsonb_array_elements(p->'shapes') loop
    if coalesce(jsonb_typeof(s), '') <> 'object' then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Forma inválida.'; end if;
    ty := s->>'type';
    if ty is null or ty not in ('pen', 'arrow', 'rect', 'ellipse') then
      raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Tipo de forma não permitido.'; end if;
    if coalesce(s->>'color', '') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Cor inválida.'; end if;
    if coalesce(jsonb_typeof(s->'width'), '') <> 'number' then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Espessura inválida.'; end if;
    w := (s->>'width')::numeric;
    if w < 0.002 or w > 0.05 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Espessura fora do intervalo.'; end if;
    pts := s->'points';
    if coalesce(jsonb_typeof(pts), '') <> 'array' then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Pontos inválidos.'; end if;
    n := jsonb_array_length(pts);
    if (ty = 'pen' and (n < 1 or n > 500)) or (ty <> 'pen' and n <> 2) then
      raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Número de pontos inválido.'; end if;
    total := total + n;
    if total > 2000 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Máximo de 2000 pontos.'; end if;
    out_pts := '[]';
    for pt in select value from jsonb_array_elements(pts) loop
      if coalesce(jsonb_typeof(pt), '') <> 'array' then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Ponto inválido.'; end if;
      if jsonb_array_length(pt) <> 2 or coalesce(jsonb_typeof(pt->0), '') <> 'number' or coalesce(jsonb_typeof(pt->1), '') <> 'number' then
        raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Ponto inválido.'; end if;
      x := (pt->>0)::numeric; y := (pt->>1)::numeric;
      if x < 0 or x > 1 or y < 0 or y > 1 then raise exception 'anotacao_invalida' using errcode = '22023', detail = 'Coordenada fora do fotograma.'; end if;
      out_pts := out_pts || jsonb_build_array(jsonb_build_array(round(x, 4), round(y, 4)));
    end loop;
    out_shapes := out_shapes || jsonb_build_array(jsonb_build_object('type', ty, 'color', lower(s->>'color'), 'width', round(w, 4), 'points', out_pts));
  end loop;
  return jsonb_build_object('v', 1, 'shapes', out_shapes);
end $$;

-- o desenho, como o texto, não se reescreve depois de gravado
create or replace function public.media_comments_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'comentarios_nao_se_apagam' using errcode = '42501'; end if;
  if (new.workspace_id, new.asset_id, new.version_id, new.parent_id, new.t_ms, new.body, new.author_id, new.author_label, new.created_at, new.annotation)
     is distinct from (old.workspace_id, old.asset_id, old.version_id, old.parent_id, old.t_ms, old.body, old.author_id, old.author_label, old.created_at, old.annotation) then
    raise exception 'comentarios_nao_se_editam' using errcode = '42501';
  end if;
  return new;
end $$;

create or replace function public._review_comment_json(c public.media_comments) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'parent_id', c.parent_id, 't_ms', c.t_ms, 'body', c.body,
    'author', coalesce(c.author_label, 'alguém'), 'author_id', c.author_id, 'at', c.created_at,
    'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by_label, 'annotation', c.annotation)
$$;

-- A mesma função com p_annotation opcional no fim (drop + create na mesma transação: não há instante sem a função, e todas as
-- chamadas antigas resolvem para esta; manter as duas faria as chamadas de 3 a 6 argumentos ambíguas).
drop function if exists public.media_review_comment(text, uuid, text, int, uuid, text);
create or replace function public.media_review_comment(p_ws text, p_version uuid, p_body text, p_t_ms int default null,
                                                       p_parent uuid default null, p_token text default null,
                                                       p_annotation jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid; c media_comments; par media_comments; t int := p_t_ms; ann jsonb;
begin
  uid := public._review_read(p_ws, p_token);
  perform public._content_require('review.comment', p_ws, p_token, 'media.review.comment', p_version::text);
  select * into v from media_versions where id = p_version and workspace_id = p_ws and state = 'pronta';
  select * into a from media_assets where id = v.asset_id and lifecycle = 'ativo';
  if v.id is null or a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  if coalesce(btrim(p_body), '') = '' then raise exception 'comentario_vazio' using errcode = '22023'; end if;
  if char_length(p_body) > 4000 then raise exception 'comentario_longo' using errcode = '22023'; end if;
  if t is not null and (t < 0 or t > 36000000) then raise exception 'momento_invalido' using errcode = '22023'; end if;
  if p_parent is not null then
    select * into par from media_comments where id = p_parent;
    if par.id is null or par.version_id <> v.id or par.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
    t := par.t_ms;
  end if;
  if p_annotation is not null and p_annotation <> 'null'::jsonb then
    if p_parent is not null then raise exception 'anotacao_em_resposta' using errcode = '22023', detail = 'As respostas não levam desenho.'; end if;
    if t is null then raise exception 'anotacao_sem_momento' using errcode = '22023', detail = 'O desenho precisa do momento do vídeo.'; end if;
    if not (v.source = 'upload' and v.storage_path is not null and coalesce(v.mime, '') like 'video/%') then
      raise exception 'anotacao_so_em_ficheiro' using errcode = '22023', detail = 'Só se desenha em vídeos guardados na app.'; end if;
    ann := public._review_annotation(p_annotation);
  end if;
  insert into media_comments (workspace_id, asset_id, version_id, parent_id, t_ms, body, author_id, author_label, annotation)
  values (p_ws, a.id, v.id, p_parent, t, btrim(p_body), uid, public._media_label(uid), ann) returning * into c;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'media.commented', 'media_asset', a.id::text,
          jsonb_build_object('version_id', v.id, 'comment_id', c.id, 't_ms', c.t_ms, 'annotated', ann is not null,
                             'shapes', coalesce(jsonb_array_length(ann->'shapes'), 0)));
  return public._review_comment_json(c);
end $$;

revoke all on function public._review_annotation(jsonb) from public, anon, authenticated;
revoke all on function public.media_review_comment(text, uuid, text, int, uuid, text, jsonb) from public, anon;
grant execute on function public.media_review_comment(text, uuid, text, int, uuid, text, jsonb) to authenticated;

/* Rollback (compatível com o código anterior, que não envia p_annotation):
   drop function if exists public.media_review_comment(text, uuid, text, int, uuid, text, jsonb);
   -- repor public.media_review_comment(text, uuid, text, int, uuid, text), public._review_comment_json e public.media_comments_guard
   -- de 20261103153227_w5_media_review.sql (com os mesmos revoke/grant);
   drop function if exists public._review_annotation(jsonb);
   alter table public.media_comments drop constraint if exists media_comments_annotation_check;
   alter table public.media_comments drop column if exists annotation;   -- só depois de exportar os desenhos que se queiram guardar */
