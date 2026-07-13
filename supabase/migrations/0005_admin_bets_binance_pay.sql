-- supabase/migrations/0005_admin_bets_binance_pay.sql
-- Objectif :
--   1. Seuls les admins peuvent créer des "bets" (paris) et des
--      "prediction_events" (prédictions). Tout le monde (authenticated)
--      peut les LIRE.
--   2. Les users ne peuvent que "miser" (wager) sur un bet/prediction
--      existant, jamais modifier ou créer les objets eux-mêmes.
--   3. Le paiement se fait hors-chaîne (Binance Pay / dépôt USDT-TRC20)
--      et n'est confirmé QUE par l'edge function `confirm-wager-payment`
--      (service_role), jamais directement par le client. Aucune policy
--      UPDATE authenticated n'existe donc sur `wagers` pour le champ
--      status → un user ne peut pas s'auto-confirmer.

-- ---------- RÔLE ADMIN ----------
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_admin from public.profiles where auth_uid = auth.uid()),
    false
  )
$$;

-- Passer un compte admin (à exécuter manuellement / via dashboard, jamais depuis le client) :
--   update public.profiles set is_admin = true where public_key = '<pubkey>';

-- ---------- BETS (paris à options multiples, créés par un admin) ----------
create table public.bets (
  id                text primary key,
  title             text not null,
  description       text not null default '',
  category          text not null default 'general',
  option_labels     jsonb not null,               -- ["Oui","Non"] ou plus
  min_stake         numeric(20,6) not null default 1,
  staking_deadline  timestamptz not null,
  voting_deadline   timestamptz not null,
  status            text not null default 'open'
                      check (status in ('open','staking_closed','settled','cancelled')),
  winning_option    text,
  creator_public_key text not null references public.profiles(public_key),
  created_at        timestamptz not null default now()
);

alter table public.bets enable row level security;

create policy "bets_select_all"
  on public.bets for select
  to authenticated
  using (true);

create policy "bets_insert_admin_only"
  on public.bets for insert
  to authenticated
  with check (public.is_admin() and creator_public_key = public.current_pubkey());

create policy "bets_update_admin_only"
  on public.bets for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ---------- PREDICTION_EVENTS : restreindre la création aux admins ----------
-- (la table existe depuis 0004 avec une policy "tout le monde peut créer" ;
--  on la resserre ici sans casser le SELECT existant)
drop policy if exists "prediction_events_insert_all" on public.prediction_events;

create policy "prediction_events_insert_admin_only"
  on public.prediction_events for insert
  to authenticated
  with check (public.is_admin() and creator_public_key = public.current_pubkey());

-- ---------- WAGERS (mise d'un user sur un bet OU une prediction) ----------
-- amount_unique : le montant EXACT (6 décimales, précision TRC20) que
-- l'user doit envoyer sur l'adresse de dépôt centrale. Il sert
-- d'identifiant de facto du paiement puisque l'adresse est partagée par
-- tous les paris en attente : deux wagers "pending_payment" ne peuvent
-- jamais avoir le même amount_unique (contrainte d'unicité partielle).
create table public.wagers (
  id                  uuid primary key default gen_random_uuid(),
  bet_id              text references public.bets(id) on delete cascade,
  prediction_event_id text references public.prediction_events(id) on delete cascade,
  user_public_key     text not null references public.profiles(public_key),
  chosen_option       text not null,               -- option label OU 'yes'/'no'
  amount_requested    numeric(20,6) not null check (amount_requested > 0),
  amount_unique       numeric(20,6) not null,
  deposit_address     text not null,
  status              text not null default 'pending_payment'
                        check (status in ('pending_payment','confirmed','rejected','expired')),
  tx_id               text,
  reject_reason       text,
  created_at          timestamptz not null default now(),
  confirmed_at        timestamptz,
  check (
    (bet_id is not null and prediction_event_id is null) or
    (bet_id is null and prediction_event_id is not null)
  )
);

-- Un seul wager "pending_payment" actif ne peut réutiliser un montant
-- unique déjà pris (anti-collision de paiement pendant qu'il est en attente).
create unique index wagers_amount_unique_pending_idx
  on public.wagers (amount_unique)
  where status = 'pending_payment';

create index wagers_user_idx on public.wagers (user_public_key, status);
create index wagers_bet_idx on public.wagers (bet_id);
create index wagers_prediction_idx on public.wagers (prediction_event_id);

alter table public.wagers enable row level security;

-- Visible par tout le monde (comme demandé : paris/prédictions et les
-- mises associées sont publics — seul le montant du wallet central et le
-- tx_id, déjà publics sur la blockchain, apparaissent).
create policy "wagers_select_all"
  on public.wagers for select
  to authenticated
  using (true);

-- Un user ne peut créer QUE sa propre mise, et uniquement à l'état initial.
create policy "wagers_insert_own"
  on public.wagers for insert
  to authenticated
  with check (
    user_public_key = public.current_pubkey()
    and status = 'pending_payment'
  );

-- IMPORTANT : aucune policy UPDATE pour "authenticated". Le passage
-- pending_payment -> confirmed/rejected ne peut se faire que via
-- l'edge function confirm-wager-payment, qui utilise la service_role key
-- et contourne donc RLS. Un user ne peut jamais s'auto-confirmer.

-- ---------- PROCESSED_DEPOSITS (anti réutilisation d'un txId) ----------
create table public.processed_deposits (
  tx_id        text primary key,
  wager_id     uuid not null references public.wagers(id) on delete cascade,
  amount       numeric(20,6) not null,
  processed_at timestamptz not null default now()
);

alter table public.processed_deposits enable row level security;
-- Aucune policy => accès refusé à "authenticated", uniquement service_role
-- (utilisé par l'edge function) peut lire/écrire cette table.

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.bets;
alter publication supabase_realtime add table public.wagers;
