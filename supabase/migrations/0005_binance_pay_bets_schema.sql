-- supabase/migrations/0005_binance_pay_bets_schema.sql
-- Schéma pour les paris centralisés via Binance Pay et validation automatique

-- 1. Ajout de la colonne is_admin aux profils
alter table public.profiles add column if not exists is_admin boolean not null default false;

-- 2. Création de la table bets (paris créés par les admins)
create table if not exists public.bets (
  id                    text primary key,
  creator_id            text not null references public.profiles(public_key) on delete cascade,
  title                 text not null,
  description           text,
  category              text not null,
  option_labels         text[] not null,
  min_stake             numeric not null,
  staking_deadline      timestamptz not null,
  voting_deadline       timestamptz not null,
  status                text not null default 'open' check (status in ('open', 'voting', 'settled', 'refunded')),
  winning_option        text,
  created_at            timestamptz not null default now()
);

-- Index pour les recherches rapides
create index if not exists bets_status_idx on public.bets (status);
create index if not exists bets_staking_deadline_idx on public.bets (staking_deadline);

-- RLS sur bets
alter table public.bets enable row level security;

drop policy if exists "bets_select_all" on public.bets;
create policy "bets_select_all"
  on public.bets for select
  to authenticated
  using (true);

drop policy if exists "bets_insert_admin" on public.bets;
create policy "bets_insert_admin"
  on public.bets for insert
  to authenticated
  with check (
    creator_id = current_pubkey()
    and exists (
      select 1 from public.profiles p
      where p.auth_uid = auth.uid() and p.is_admin = true
    )
  );

drop policy if exists "bets_update_admin" on public.bets;
create policy "bets_update_admin"
  on public.bets for update
  to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.auth_uid = auth.uid() and p.is_admin = true
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.auth_uid = auth.uid() and p.is_admin = true
  ));

-- 3. Création de la table bet_stakes (mises posées par les utilisateurs)
create table if not exists public.bet_stakes (
  id                    uuid primary key default gen_random_uuid(),
  bet_id                text not null references public.bets(id) on delete cascade,
  staker_id             text not null references public.profiles(public_key) on delete cascade,
  option_label          text not null,
  amount                numeric not null,
  amount_exact          numeric not null unique, -- Montant exact avec centimes uniques générés pour distinction
  status                text not null default 'pending_payment' check (status in ('pending_payment', 'confirmed', 'rejected')),
  tx_id                 text unique, -- Hash de la transaction Binance Pay/USDT TRC20
  created_at            timestamptz not null default now()
);

-- Index pour les vérifications d'unicité et de liaison
create index if not exists bet_stakes_bet_id_idx on public.bet_stakes (bet_id);
create index if not exists bet_stakes_staker_id_idx on public.bet_stakes (staker_id);
create index if not exists bet_stakes_amount_exact_idx on public.bet_stakes (amount_exact);
create index if not exists bet_stakes_tx_id_idx on public.bet_stakes (tx_id);

-- RLS sur bet_stakes
alter table public.bet_stakes enable row level security;

drop policy if exists "bet_stakes_select_all" on public.bet_stakes;
create policy "bet_stakes_select_all"
  on public.bet_stakes for select
  to authenticated
  using (true);

drop policy if exists "bet_stakes_insert_user" on public.bet_stakes;
create policy "bet_stakes_insert_user"
  on public.bet_stakes for insert
  to authenticated
  with check (staker_id = current_pubkey());

drop policy if exists "bet_stakes_update_user" on public.bet_stakes;
create policy "bet_stakes_update_user"
  on public.bet_stakes for update
  to authenticated
  using (staker_id = current_pubkey())
  with check (staker_id = current_pubkey());

-- 4. Création de la table processed_deposits (anti double dépense / idempotency)
create table if not exists public.processed_deposits (
  tx_id                 text primary key,
  bet_stake_id          uuid not null references public.bet_stakes(id) on delete cascade,
  amount                numeric not null,
  processed_at          timestamptz not null default now()
);

-- RLS sur processed_deposits
alter table public.processed_deposits enable row level security;

drop policy if exists "processed_deposits_select_all" on public.processed_deposits;
create policy "processed_deposits_select_all"
  on public.processed_deposits for select
  to authenticated
  using (true);

-- 5. Restriction des prédictions (prediction_events) aux administrateurs uniquement
drop policy if exists "prediction_events_insert_all" on public.prediction_events;

drop policy if exists "prediction_events_insert_admin" on public.prediction_events;
create policy "prediction_events_insert_admin"
  on public.prediction_events for insert
  to authenticated
  with check (
    creator_public_key = current_pubkey()
    and exists (
      select 1 from public.profiles p
      where p.auth_uid = auth.uid() and p.is_admin = true
    )
  );

-- 6. Publication Realtime pour les nouveaux paris et mises
do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_class c on pr.prrelid = c.oid
    join pg_publication p on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime' and c.relname = 'bets'
  ) then
    alter publication supabase_realtime add table public.bets;
  end if;

  if not exists (
    select 1 from pg_publication_rel pr
    join pg_class c on pr.prrelid = c.oid
    join pg_publication p on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime' and c.relname = 'bet_stakes'
  ) then
    alter publication supabase_realtime add table public.bet_stakes;
  end if;

  if not exists (
    select 1 from pg_publication_rel pr
    join pg_class c on pr.prrelid = c.oid
    join pg_publication p on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime' and c.relname = 'processed_deposits'
  ) then
    alter publication supabase_realtime add table public.processed_deposits;
  end if;
end $$;
