-- W8 · Notificações por evento (PRD FR-15-05 e a parte "notificações" de FR-14-02). ADR-0040.
-- Expand: 1 flag, 6 tabelas fechadas à API (catálogo de canais e de eventos, preferências do cliente, preferências pessoais,
-- silêncio por cliente e contadores de supressão). Nenhuma capacidade nova: o cliente é gerido com settings.manage (a de
-- Definições) e as preferências pessoais são de quem recebe (tasks.read no cliente, a mesma regra de _notify).
-- Esta parte não muda comportamento nenhum; _notify só passa a ler as preferências em p2 e só com a flag ligada para quem recebe.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('notifications.prefs', 'Preferências de notificações', 'Definições', 'ws', 'owner',
   'Que eventos geram notificação e em que canal, por cliente e por pessoa, com eventos obrigatórios e silêncio por cliente (FR-15-05, FR-14-02). Só "na app" envia; email e resumo diário ficam guardados como preferência até haver envio.')
on conflict (key) do nothing;

-- ───────────── catálogo (dados, iguais para todos os clientes) ─────────────
create table if not exists public.notification_channel_defs (
  key text primary key check (key ~ '^[a-z_]{2,20}$'),
  label text not null,
  available boolean not null,
  unavailable_reason text check (available or unavailable_reason is not null),
  sort int not null default 100
);
insert into public.notification_channel_defs (key, label, available, unavailable_reason, sort) values
  ('in_app', 'Na app', true, null, 10),
  ('email', 'Email', false, 'Ainda não há domínio nem serviço de envio configurado. A preferência fica guardada e passa a valer quando o envio existir; até lá nenhum email é enviado.', 20),
  ('digest', 'Resumo diário', false, 'O resumo diário ainda não existe. A preferência fica guardada; até lá nada é enviado.', 30)
on conflict (key) do update set label = excluded.label, available = excluded.available, unavailable_reason = excluded.unavailable_reason, sort = excluded.sort;

-- Um tipo por valor de notifications.kind (teste em w8_notif.sql garante que nenhum fica de fora).
-- mandatory: nunca se desliga nem é silenciado (nem pelo cliente nem pela pessoa).
create table if not exists public.notification_event_defs (
  kind text primary key check (kind ~ '^[a-z_]{3,40}$'),
  group_key text not null check (group_key in ('tarefas', 'guioes', 'automacao')),
  label text not null,
  description text not null,
  recipients text not null,
  channels text[] not null check (cardinality(channels) >= 1 and 'in_app' = any (channels)),
  default_channels text[] not null check (default_channels <@ channels and 'in_app' = any (default_channels)),
  mandatory boolean not null default false,
  mandatory_reason text check (not mandatory or mandatory_reason is not null),
  sort int not null default 100
);
insert into public.notification_event_defs (kind, group_key, label, description, recipients, channels, default_channels, mandatory, mandatory_reason, sort) values
  ('task_assigned', 'tarefas', 'Tarefa atribuída a mim', 'Uma tarefa nova ou que passou para ti.', 'Quem fica responsável', '{in_app,email,digest}', '{in_app}', true, 'Atribuições não se desligam: ninguém pode ficar com trabalho sem saber.', 10),
  ('task_auto', 'tarefas', 'Tarefa criada automaticamente', 'Uma automação criou uma tarefa e atribuiu-ta.', 'Quem fica responsável', '{in_app,email,digest}', '{in_app}', true, 'Atribuições não se desligam: ninguém pode ficar com trabalho sem saber.', 20),
  ('task_delegated', 'tarefas', 'Tarefa delegada a mim', 'Alguém te delegou uma tarefa.', 'Quem fica responsável', '{in_app,email,digest}', '{in_app}', true, 'Atribuições não se desligam: ninguém pode ficar com trabalho sem saber.', 30),
  ('task_unassigned', 'tarefas', 'Tarefa passou para outra pessoa', 'Uma tarefa que era tua foi atribuída a outra pessoa.', 'Quem era responsável', '{in_app,email,digest}', '{in_app}', false, null, 40),
  ('task_mention', 'tarefas', 'Menção ou comentário numa tarefa', 'Alguém te mencionou ou comentou uma tarefa tua.', 'Quem é mencionado e quem é responsável', '{in_app,email,digest}', '{in_app}', false, null, 50),
  ('task_blocked', 'tarefas', 'Tarefa que criei ficou bloqueada', 'Uma tarefa que criaste ficou bloqueada, com o motivo.', 'Quem criou a tarefa', '{in_app,email,digest}', '{in_app}', false, null, 60),
  ('task_done', 'tarefas', 'Tarefa que criei foi concluída', 'Uma tarefa que criaste foi dada como feita.', 'Quem criou a tarefa', '{in_app,email,digest}', '{in_app}', false, null, 70),
  ('script_assigned', 'guioes', 'Guião atribuído a mim', 'Ficaste responsável por um guião.', 'Quem fica responsável', '{in_app,email,digest}', '{in_app}', true, 'Atribuições não se desligam: ninguém pode ficar com trabalho sem saber.', 110),
  ('script_mention', 'guioes', 'Menção num guião', 'Alguém te mencionou num comentário de um guião.', 'Quem é mencionado', '{in_app,email,digest}', '{in_app}', false, null, 120),
  ('script_comment', 'guioes', 'Resposta a um comentário meu', 'Alguém respondeu a um comentário teu num guião.', 'Quem escreveu o comentário', '{in_app,email,digest}', '{in_app}', false, null, 130),
  ('automation_error', 'automacao', 'Erro de automação', 'Uma execução dos agentes falhou de vez e foi para a fila de exceções.', 'Quem configura os agentes do cliente', '{in_app,email,digest}', '{in_app}', true, 'Erros de automação chegam sempre a quem gere os agentes: sem isso a falha passava despercebida.', 210)
on conflict (kind) do update set group_key = excluded.group_key, label = excluded.label, description = excluded.description, recipients = excluded.recipients,
  channels = excluded.channels, default_channels = excluded.default_channels, mandatory = excluded.mandatory, mandatory_reason = excluded.mandatory_reason, sort = excluded.sort;

-- ───────────── preferências ─────────────
-- Do cliente: só as linhas que diferem da predefinição do catálogo. required = obrigatório neste cliente (só "na app").
create table if not exists public.notification_ws_prefs (
  workspace_id text not null references public.clients(id),
  kind text not null references public.notification_event_defs(kind),
  channel text not null references public.notification_channel_defs(key),
  enabled boolean not null,
  required boolean not null default false check (not required or (enabled and channel = 'in_app')),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (workspace_id, kind, channel)
);

-- Da pessoa, por cliente. Só as linhas que diferem da predefinição.
create table if not exists public.notification_user_prefs (
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  kind text not null references public.notification_event_defs(kind),
  channel text not null references public.notification_channel_defs(key),
  enabled boolean not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, workspace_id, kind, channel)
);

-- Silenciar um cliente (para a própria pessoa). muted_until nulo = até desligar.
create table if not exists public.notification_mutes (
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  muted_until timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, workspace_id)
);

-- Contagem leve das notificações não criadas por preferência (uma linha por pessoa, cliente, tipo, motivo e dia UTC).
-- Não há um audit_events por supressão (seria ruído); as mudanças de preferência é que ficam no histórico. ADR-0040.
create table if not exists public.notification_suppressions (
  workspace_id text not null references public.clients(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  reason text not null check (reason in ('org_off', 'user_off', 'muted')),
  day date not null,
  n int not null default 1 check (n >= 1),
  last_at timestamptz not null default now(),
  last_dedup text,
  primary key (workspace_id, user_id, kind, reason, day)
);
create index if not exists notification_suppressions_ws_day on public.notification_suppressions (workspace_id, day);

alter table public.notification_channel_defs enable row level security;
alter table public.notification_event_defs enable row level security;
alter table public.notification_ws_prefs enable row level security;
alter table public.notification_user_prefs enable row level security;
alter table public.notification_mutes enable row level security;
alter table public.notification_suppressions enable row level security;
revoke all on public.notification_channel_defs, public.notification_event_defs, public.notification_ws_prefs,
  public.notification_user_prefs, public.notification_mutes, public.notification_suppressions from anon, authenticated;   -- só pelas RPCs

/* Rollback (compatível; depois de reverter p2):
   drop table if exists public.notification_suppressions, public.notification_mutes, public.notification_user_prefs,
     public.notification_ws_prefs, public.notification_event_defs, public.notification_channel_defs;
   delete from feature_flags where key = 'notifications.prefs'; delete from feature_flag_defs where key = 'notifications.prefs'; */
