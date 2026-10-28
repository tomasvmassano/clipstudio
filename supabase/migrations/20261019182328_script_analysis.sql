-- 20261019182328 script_analysis (exportado do Supabase a 28/10/2026; segredos tapados)
create table public.script_analysis (
  reel_id text primary key references public.reels(id) on delete cascade,
  language text,
  hook text,                 -- primeira frase / gancho
  tese text,                 -- a afirmação central
  alvo text,                 -- o que/quem é atacado ou desafiado
  formato text,              -- monólogo, podcast clip, prank, reação, lista, história...
  gatilho text,              -- emoção/mecanismo que puxa comentário e share
  estrutura text,            -- beats do guião
  porque_viraliza text,
  polemica int check (polemica between 0 and 10),
  risco_plataforma text check (risco_plataforma in ('baixo','medio','alto')),
  angulo_numeiro text,       -- como o Numeiro pode usar o mecanismo
  analyzed_at timestamptz default now()
);
alter table public.script_analysis enable row level security;
comment on table public.script_analysis is 'Análise de cada guião viral (transcrição em reels.transcript).';

create or replace view public.v_guioes_virais with (security_invoker = true) as
  select r.owner, r.views, r.likes, r.comments, round(r.heat::numeric,2) heat, round(r.debate_idx::numeric,2) debate,
         s.polemica, s.hook, s.tese, s.alvo, s.formato, s.gatilho, s.porque_viraliza, s.angulo_numeiro, s.risco_plataforma,
         r.transcript, r.url
  from public.reels r join public.script_analysis s on s.reel_id = r.id
  order by r.views desc;;
