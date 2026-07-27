create table if not exists public.couplemon_todos (
  id uuid primary key,
  room_code text not null
    check (room_code ~ '^[A-HJ-NP-Z2-9]{16,32}$'),
  scope text not null
    check (scope in ('personal', 'couple')),
  owner_id uuid,
  text text not null
    check (char_length(btrim(text)) between 1 and 120),
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  check (
    (scope = 'personal' and owner_id is not null)
    or (scope = 'couple' and owner_id is null)
  )
);

create index if not exists couplemon_todos_room_created_idx
  on public.couplemon_todos (room_code, created_at, id);

alter table public.couplemon_todos enable row level security;
grant select, insert, update, delete on public.couplemon_todos to anon;

drop policy if exists "couplemon room read" on public.couplemon_todos;
create policy "couplemon room read"
on public.couplemon_todos for select to anon
using (
  room_code = upper(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
      ->> 'x-couplemon-room'
  )
);

drop policy if exists "couplemon room insert" on public.couplemon_todos;
create policy "couplemon room insert"
on public.couplemon_todos for insert to anon
with check (
  room_code = upper(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
      ->> 'x-couplemon-room'
  )
  and (
    (scope = 'couple' and owner_id is null)
    or (
      scope = 'personal'
      and lower(owner_id::text) = lower(
        coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
          ->> 'x-couplemon-owner'
      )
    )
  )
);

drop policy if exists "couplemon room update" on public.couplemon_todos;
create policy "couplemon room update"
on public.couplemon_todos for update to anon
using (
  room_code = upper(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
      ->> 'x-couplemon-room'
  )
  and (
    scope = 'couple'
    or lower(owner_id::text) = lower(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-couplemon-owner'
    )
  )
)
with check (
  room_code = upper(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
      ->> 'x-couplemon-room'
  )
  and (
    (scope = 'couple' and owner_id is null)
    or (
      scope = 'personal'
      and lower(owner_id::text) = lower(
        coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
          ->> 'x-couplemon-owner'
      )
    )
  )
);

drop policy if exists "couplemon room delete" on public.couplemon_todos;
create policy "couplemon room delete"
on public.couplemon_todos for delete to anon
using (
  room_code = upper(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
      ->> 'x-couplemon-room'
  )
  and (
    scope = 'couple'
    or lower(owner_id::text) = lower(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-couplemon-owner'
    )
  )
);
