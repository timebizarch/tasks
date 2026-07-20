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
