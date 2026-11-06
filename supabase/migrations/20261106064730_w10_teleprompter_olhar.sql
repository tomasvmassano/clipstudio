-- W10-11 · Teleprompter e olhar na câmara (PRD §46.1, CHG-008): GAZE-01 coluna ligada à distância, GAZE-02 linha de
-- foco e modo frase. Estende FR-03-03 e FR-03-05 (preferências por utilizador e dispositivo). ADR-0060.
-- Expand (só aditivo, compatível com o código em main): _tp_prefs_clean passa a aceitar mais cinco chaves, com limites:
--   distance_m (0,3 a 6 m), screen_in (4 a 100 polegadas ou null), column_fit (boolean), focus_pct (5 a 60 %),
--   phrase_mode (boolean). As chaves antigas e os erros (22023 para chave desconhecida ou valor inválido) ficam iguais.
--   O código em main não envia as chaves novas, por isso não muda nada para ele; tabela, RLS e grants não mudam.
-- Rollback: bloco no fim (repõe a função anterior; as chaves novas já guardadas ficam no jsonb e são ignoradas).

create or replace function public._tp_prefs_clean(p jsonb) returns jsonb language plpgsql immutable set search_path = public as $$
declare k text; out jsonb := '{}'::jsonb; act text;
begin
  if jsonb_typeof(p) <> 'object' or length(p::text) > 4000 then raise exception 'preferencias_invalidas' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('speed','font','line_height','margin','mirror_h','mirror_v','contrast','keys','confirm_on_advance',
                 'distance_m','screen_in','column_fit','focus_pct','phrase_mode') then
      raise exception 'preferencia_desconhecida: %', k using errcode = '22023';
    end if;
  end loop;
  if p ? 'speed' then out := out || jsonb_build_object('speed', least(greatest((p->>'speed')::integer, 1), 10)); end if;
  if p ? 'font' then out := out || jsonb_build_object('font', least(greatest((p->>'font')::integer, 32), 96)); end if;
  if p ? 'line_height' then out := out || jsonb_build_object('line_height', least(greatest((p->>'line_height')::numeric, 1.0), 2.2)); end if;
  if p ? 'margin' then out := out || jsonb_build_object('margin', least(greatest((p->>'margin')::integer, 0), 25)); end if;
  if p ? 'mirror_h' then out := out || jsonb_build_object('mirror_h', (p->>'mirror_h')::boolean); end if;
  if p ? 'mirror_v' then out := out || jsonb_build_object('mirror_v', (p->>'mirror_v')::boolean); end if;
  if p ? 'confirm_on_advance' then out := out || jsonb_build_object('confirm_on_advance', (p->>'confirm_on_advance')::boolean); end if;
  if p ? 'contrast' then
    if p->>'contrast' not in ('normal','alto','ambar') then raise exception 'contraste_invalido' using errcode = '22023'; end if;
    out := out || jsonb_build_object('contrast', p->>'contrast');
  end if;
  if p ? 'keys' then
    if jsonb_typeof(p->'keys') <> 'object' then raise exception 'atalhos_invalidos' using errcode = '22023'; end if;
    for act in select jsonb_object_keys(p->'keys') loop
      if act not in ('play','faster','slower','next','prev','next_block','prev_block','take','mirror','font_up','font_down','fullscreen','exit') then
        raise exception 'atalho_desconhecido: %', act using errcode = '22023';
      end if;
      if jsonb_typeof(p->'keys'->act) <> 'array' or jsonb_array_length(p->'keys'->act) > 4
         or exists (select 1 from jsonb_array_elements(p->'keys'->act) e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > 20) then
        raise exception 'atalhos_invalidos' using errcode = '22023';
      end if;
    end loop;
    out := out || jsonb_build_object('keys', p->'keys');
  end if;
  -- GAZE-01: distância e ecrã por dispositivo (o dispositivo já é a chave da linha)
  if p ? 'distance_m' then
    if jsonb_typeof(p->'distance_m') <> 'number' then raise exception 'distancia_invalida' using errcode = '22023'; end if;
    out := out || jsonb_build_object('distance_m', round(least(greatest((p->>'distance_m')::numeric, 0.3), 6.0), 2));
  end if;
  if p ? 'screen_in' then
    if jsonb_typeof(p->'screen_in') = 'null' then out := out || jsonb_build_object('screen_in', null);
    elsif jsonb_typeof(p->'screen_in') <> 'number' then raise exception 'ecra_invalido' using errcode = '22023';
    else out := out || jsonb_build_object('screen_in', round(least(greatest((p->>'screen_in')::numeric, 4), 100), 1));
    end if;
  end if;
  if p ? 'column_fit' then out := out || jsonb_build_object('column_fit', (p->>'column_fit')::boolean); end if;
  -- GAZE-02
  if p ? 'focus_pct' then
    if jsonb_typeof(p->'focus_pct') <> 'number' then raise exception 'linha_de_foco_invalida' using errcode = '22023'; end if;
    out := out || jsonb_build_object('focus_pct', least(greatest(round((p->>'focus_pct')::numeric)::integer, 5), 60));
  end if;
  if p ? 'phrase_mode' then out := out || jsonb_build_object('phrase_mode', (p->>'phrase_mode')::boolean); end if;
  return out;
end $$;

revoke all on function public._tp_prefs_clean(jsonb) from public, anon, authenticated;

/* Rollback: repor a definição de 20261028211702_w2_teleprompter.sql (secção "preferências"):
create or replace function public._tp_prefs_clean(p jsonb) returns jsonb language plpgsql immutable set search_path = public as $$
declare k text; out jsonb := '{}'::jsonb; act text;
begin
  if jsonb_typeof(p) <> 'object' or length(p::text) > 4000 then raise exception 'preferencias_invalidas' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('speed','font','line_height','margin','mirror_h','mirror_v','contrast','keys','confirm_on_advance') then
      raise exception 'preferencia_desconhecida: %', k using errcode = '22023';
    end if;
  end loop;
  if p ? 'speed' then out := out || jsonb_build_object('speed', least(greatest((p->>'speed')::integer, 1), 10)); end if;
  if p ? 'font' then out := out || jsonb_build_object('font', least(greatest((p->>'font')::integer, 32), 96)); end if;
  if p ? 'line_height' then out := out || jsonb_build_object('line_height', least(greatest((p->>'line_height')::numeric, 1.0), 2.2)); end if;
  if p ? 'margin' then out := out || jsonb_build_object('margin', least(greatest((p->>'margin')::integer, 0), 25)); end if;
  if p ? 'mirror_h' then out := out || jsonb_build_object('mirror_h', (p->>'mirror_h')::boolean); end if;
  if p ? 'mirror_v' then out := out || jsonb_build_object('mirror_v', (p->>'mirror_v')::boolean); end if;
  if p ? 'confirm_on_advance' then out := out || jsonb_build_object('confirm_on_advance', (p->>'confirm_on_advance')::boolean); end if;
  if p ? 'contrast' then
    if p->>'contrast' not in ('normal','alto','ambar') then raise exception 'contraste_invalido' using errcode = '22023'; end if;
    out := out || jsonb_build_object('contrast', p->>'contrast');
  end if;
  if p ? 'keys' then
    if jsonb_typeof(p->'keys') <> 'object' then raise exception 'atalhos_invalidos' using errcode = '22023'; end if;
    for act in select jsonb_object_keys(p->'keys') loop
      if act not in ('play','faster','slower','next','prev','next_block','prev_block','take','mirror','font_up','font_down','fullscreen','exit') then
        raise exception 'atalho_desconhecido: %', act using errcode = '22023';
      end if;
      if jsonb_typeof(p->'keys'->act) <> 'array' or jsonb_array_length(p->'keys'->act) > 4
         or exists (select 1 from jsonb_array_elements(p->'keys'->act) e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > 20) then
        raise exception 'atalhos_invalidos' using errcode = '22023';
      end if;
    end loop;
    out := out || jsonb_build_object('keys', p->'keys');
  end if;
  return out;
end $$;
revoke all on function public._tp_prefs_clean(jsonb) from public, anon, authenticated;
*/
