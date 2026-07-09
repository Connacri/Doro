-- supabase/migrations/0001_doro_messenger_schema.sql
-- Déjà appliquée sur le projet "Doro's Project" (rwzsnlfuqmfxouhfbeoi) via MCP.
-- Committer ce fichier rend l'état reproductible via `supabase db push`.

create extension if not exists pgcrypto;

-- ---------- PROFILES ----------
create table public.profiles (
  auth_uid    uuid primary key references auth.users(id) on delete cascade,
  public_key  text unique not null check (char_length(public_key) between 32 and 128),
  display_name text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

create index profiles_public_key_idx on public.profiles (public_key);
alter table public.profiles enable row level security;

create or replace function public.current_pubkey()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public_key from public.profiles where auth_uid = auth.uid()
$$;

create policy "profiles_select_all_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles_update_own_non_identity_fields"
  on public.profiles for update
  to authenticated
  using (auth_uid = auth.uid())
  with check (auth_uid = auth.uid());

-- ---------- FRIEND REQUESTS ----------
create table public.friend_requests (
  id           uuid primary key default gen_random_uuid(),
  from_pubkey  text not null references public.profiles(public_key) on delete cascade,
  to_pubkey    text not null references public.profiles(public_key) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (from_pubkey, to_pubkey),
  check (from_pubkey <> to_pubkey)
);

create index friend_requests_to_idx on public.friend_requests (to_pubkey, status);
create index friend_requests_from_idx on public.friend_requests (from_pubkey, status);
alter table public.friend_requests enable row level security;

create policy "friend_requests_select_own"
  on public.friend_requests for select
  to authenticated
  using (from_pubkey = current_pubkey() or to_pubkey = current_pubkey());

create policy "friend_requests_insert_as_sender"
  on public.friend_requests for insert
  to authenticated
  with check (from_pubkey = current_pubkey());

create policy "friend_requests_update_participant"
  on public.friend_requests for update
  to authenticated
  using (from_pubkey = current_pubkey() or to_pubkey = current_pubkey())
  with check (from_pubkey = current_pubkey() or to_pubkey = current_pubkey());

create policy "friend_requests_delete_participant"
  on public.friend_requests for delete
  to authenticated
  using (from_pubkey = current_pubkey() or to_pubkey = current_pubkey());

-- ---------- FRIENDSHIPS ----------
create table public.friendships (
  pubkey_a   text not null references public.profiles(public_key) on delete cascade,
  pubkey_b   text not null references public.profiles(public_key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (pubkey_a, pubkey_b),
  check (pubkey_a < pubkey_b)
);

alter table public.friendships enable row level security;

create policy "friendships_select_own"
  on public.friendships for select
  to authenticated
  using (pubkey_a = current_pubkey() or pubkey_b = current_pubkey());

create or replace function public.handle_friend_request_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  a text;
  b text;
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    if new.from_pubkey < new.to_pubkey then
      a := new.from_pubkey; b := new.to_pubkey;
    else
      a := new.to_pubkey; b := new.from_pubkey;
    end if;
    insert into public.friendships (pubkey_a, pubkey_b)
      values (a, b)
      on conflict do nothing;
    delete from public.friend_requests
      where from_pubkey = new.to_pubkey and to_pubkey = new.from_pubkey;
  end if;
  return new;
end;
$$;

create trigger trg_friend_request_accepted
  after update on public.friend_requests
  for each row execute function public.handle_friend_request_accepted();

-- ---------- MESSAGES ----------
create table public.messages (
  id           uuid primary key default gen_random_uuid(),
  from_pubkey  text not null references public.profiles(public_key) on delete cascade,
  to_pubkey    text not null references public.profiles(public_key) on delete cascade,
  body         text not null,
  status       text not null default 'sent' check (status in ('sent','delivered','read')),
  created_at   timestamptz not null default now(),
  delivered_at timestamptz,
  read_at      timestamptz,
  check (from_pubkey <> to_pubkey)
);

create index messages_conversation_idx on public.messages (least(from_pubkey, to_pubkey), greatest(from_pubkey, to_pubkey), created_at);
create index messages_to_idx on public.messages (to_pubkey, status);
alter table public.messages enable row level security;

create policy "messages_select_participant"
  on public.messages for select
  to authenticated
  using (from_pubkey = current_pubkey() or to_pubkey = current_pubkey());

create policy "messages_insert_if_friends"
  on public.messages for insert
  to authenticated
  with check (
    from_pubkey = current_pubkey()
    and exists (
      select 1 from public.friendships f
      where (f.pubkey_a = least(from_pubkey, to_pubkey) and f.pubkey_b = greatest(from_pubkey, to_pubkey))
    )
  );

create policy "messages_update_status_by_recipient"
  on public.messages for update
  to authenticated
  using (to_pubkey = current_pubkey())
  with check (to_pubkey = current_pubkey());

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.friend_requests;
alter publication supabase_realtime add table public.friendships;
