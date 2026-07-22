-- Cole isto no Supabase: menu SQL Editor > New query > Run.
-- Cria a tabela de tarefas e liga a segurança por usuário (RLS),
-- pra que cada login só enxergue as próprias tarefas.

create table if not exists tasks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  text        text not null,
  bucket      text not null default 'inbox',
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table tasks enable row level security;

create policy "cada um vê e mexe só nas suas tarefas"
  on tasks for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- v2: tag de área (texto livre), urgência e prazo — todos opcionais.
-- Cole e rode isto separadamente no SQL Editor (tabela já existe).
alter table tasks add column if not exists area text;
alter table tasks add column if not exists urgent boolean not null default false;
alter table tasks add column if not exists due_date date;

-- v2.2: campo "aguardando quem" (só usado no balde Aguardando).
alter table tasks add column if not exists waiting_on text;

-- v2.3: rastreabilidade — quando foi concluída e quando foi "limpa" da vista.
-- "limpar concluídas" agora só marca cleared_at (não apaga mais a linha),
-- pra dar pra ver o histórico de tudo que já foi feito.
alter table tasks add column if not exists done_at timestamptz;
alter table tasks add column if not exists cleared_at timestamptz;

-- v2.4: origem da captura (ex: 'slack'). Preenchido pela automação do
-- Make; captura manual pelo app deixa null. Mostra uma tag "via Slack".
alter table tasks add column if not exists source text;

-- v2.5: subtarefas ("próximos passos"). Uma subtask é uma tarefa normal
-- com parent_id apontando pra outra tarefa — um nível só de aninhamento.
-- Apagar a tarefa-mãe apaga os passos junto (on delete cascade).
alter table tasks add column if not exists parent_id uuid references tasks(id) on delete cascade;

-- v2.6: sincronização Slack ⇄ conclusão. Guarda em qual canal/mensagem
-- a tarefa nasceu no Slack, pra depois marcar ✅ lá quando for concluída
-- (e vice-versa: reação ✅ no Slack marca done aqui). Preenchido só pela
-- automação do Make; captura manual pelo app deixa null.
alter table tasks add column if not exists slack_channel text;
alter table tasks add column if not exists slack_ts text;

-- v2.7: link de visualização somente-leitura, pra compartilhar com o líder
-- sem dar login. Quem tem o token vê Hoje/Esta semana/Aguardando + o que
-- foi concluído nos últimos 7 dias, via a função abaixo — nunca a tabela
-- direto (o RLS normal continua exigindo login pra qualquer outro acesso).
create table if not exists share_tokens (
  token       uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  created_at  timestamptz not null default now(),
  revoked     boolean not null default false
);

alter table share_tokens enable row level security;

create policy "cada um vê e mexe só nos próprios links de compartilhamento"
  on share_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- security definer: roda ignorando o RLS de "tasks" acima, mas só devolve
-- o que a própria função decide expor — nunca a tabela inteira.
create or replace function get_shared_tasks(p_token uuid)
returns setof tasks
language sql
security definer
set search_path = public
as $$
  select t.*
  from tasks t
  join share_tokens s on s.user_id = t.user_id
  where s.token = p_token
    and s.revoked = false
    and t.cleared_at is null
    and (
      (t.done = false and t.bucket in ('hoje', 'semana', 'aguardando'))
      or (t.done = true and t.done_at >= now() - interval '7 days')
    )
$$;

grant execute on function get_shared_tasks(uuid) to anon;

-- checagem separada de validade: sem isso, um link revogado e um dia sem
-- nenhuma tarefa ficam indistinguíveis (os dois retornam lista vazia).
create or replace function is_valid_share_token(p_token uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(select 1 from share_tokens where token = p_token and revoked = false);
$$;

grant execute on function is_valid_share_token(uuid) to anon;
