-- Таблица, которую использует SupabaseService
create table if not exists public.bookmarks (
  id         bigint generated always as identity primary key,
  address    text not null,
  latitude   double precision not null,
  longitude  double precision not null,
  type       text not null check (type in ('bookmark','history','home','work')),
  created_at timestamptz not null default now()
);

alter table public.bookmarks enable row level security;

-- ВНИМАНИЕ: в приложении нет авторизации, поэтому политика ниже открывает
-- таблицу всем, у кого есть publishable-ключ. Для личного использования —
-- нормально; для публичного релиза добавьте Supabase Auth и колонку user_id.
create policy "anon full access" on public.bookmarks
  for all to anon using (true) with check (true);
