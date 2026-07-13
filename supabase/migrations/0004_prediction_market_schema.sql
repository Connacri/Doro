-- supabase/migrations/0004_prediction_market_schema.sql
-- Schéma pour la persistance des événements de prédiction, ordres et transactions.

-- ---------- EVENTS ----------
create table public.prediction_events (
  id                    text primary key,
  question              text not null,
  creator_id            text not null references public.profiles(public_key) on delete cascade,
  creator_public_key    text not null,
  oracle_address        text not null,
  oracle_public_key     text not null,
  created_at            bigint not null,
  closes_at             bigint not null,
  creator_signature     text not null,
  winning_outcome       text check (winning_outcome in ('yes', 'no')),
  resolution_signature  text,
  resolved_at           bigint
);

alter table public.prediction_events enable row level security;

create policy "prediction_events_select_all"
  on public.prediction_events for select
  to authenticated
  using (true);

create policy "prediction_events_insert_all"
  on public.prediction_events for insert
  to authenticated
  with check (creator_public_key = current_pubkey());

create policy "prediction_events_update_oracle"
  on public.prediction_events for update
  to authenticated
  using (oracle_public_key = current_pubkey())
  with check (oracle_public_key = current_pubkey());

-- ---------- ORDERS ----------
create table public.share_orders (
  id               text primary key,
  event_id         text not null references public.prediction_events(id) on delete cascade,
  outcome          text not null check (outcome in ('yes', 'no')),
  maker_id         text not null,
  maker_public_key text not null,
  side             text not null check (side in ('buy', 'sell')),
  shares           text not null, -- BigInt sérialisé
  filled_shares    text not null, -- BigInt sérialisé
  price_per_share  text not null, -- BigInt sérialisé
  timestamp        bigint not null,
  signature        text not null,
  cancelled        boolean not null default false
);

alter table public.share_orders enable row level security;

create policy "share_orders_select_all"
  on public.share_orders for select
  to authenticated
  using (true);

create policy "share_orders_insert_maker"
  on public.share_orders for insert
  to authenticated
  with check (maker_public_key = current_pubkey());

create policy "share_orders_update_all"
  on public.share_orders for update
  to authenticated
  using (true)
  with check (true);

-- ---------- TRADES (BETS) ----------
create table public.prediction_trades (
  id             text primary key,
  order_id       text not null references public.share_orders(id) on delete cascade,
  seller_id      text not null,
  buyer_id       text not null,
  amount         text not null, -- BigInt sérialisé
  price_per_unit text not null, -- BigInt sérialisé
  currency       text not null,
  timestamp      bigint not null,
  status         text not null,
  tx_id          text
);

alter table public.prediction_trades enable row level security;

create policy "prediction_trades_select_all"
  on public.prediction_trades for select
  to authenticated
  using (true);

create policy "prediction_trades_insert_all"
  on public.prediction_trades for insert
  to authenticated
  with check (true);

create policy "prediction_trades_update_all"
  on public.prediction_trades for update
  to authenticated
  using (true)
  with check (true);

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.prediction_events;
alter publication supabase_realtime add table public.share_orders;
alter publication supabase_realtime add table public.prediction_trades;
