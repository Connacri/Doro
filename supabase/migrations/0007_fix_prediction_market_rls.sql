-- Drop old policies
drop policy if exists "prediction_events_insert_all" on public.prediction_events;
drop policy if exists "prediction_events_insert_admin" on public.prediction_events;
drop policy if exists "prediction_events_update_owner" on public.prediction_events;
drop policy if exists "prediction_events_update_oracle" on public.prediction_events;
drop policy if exists "prediction_events_delete_owner" on public.prediction_events;

-- Recreate policies with creator_id and oracle_address (starting with 0x)
create policy "prediction_events_insert_admin"
  on public.prediction_events for insert
  to authenticated
  with check (
    creator_id = current_pubkey()
    and exists (
      select 1 from public.profiles p
      where p.auth_uid = auth.uid() and p.is_admin = true
    )
  );

create policy "prediction_events_update_owner"
  on public.prediction_events for update
  to authenticated
  using (creator_id = current_pubkey())
  with check (creator_id = current_pubkey());

create policy "prediction_events_update_oracle"
  on public.prediction_events for update
  to authenticated
  using (oracle_address = current_pubkey())
  with check (oracle_address = current_pubkey());

create policy "prediction_events_delete_owner"
  on public.prediction_events for delete
  to authenticated
  using (creator_id = current_pubkey());

-- Cascading RLS delete policies for orders and trades
drop policy if exists "share_orders_delete_policy" on public.share_orders;
create policy "share_orders_delete_policy"
  on public.share_orders for delete
  to authenticated
  using (
    maker_id = current_pubkey()
    or exists (
      select 1 from public.prediction_events e
      where e.id = event_id and e.creator_id = current_pubkey()
    )
  );

drop policy if exists "prediction_trades_delete_policy" on public.prediction_trades;
create policy "prediction_trades_delete_policy"
  on public.prediction_trades for delete
  to authenticated
  using (
    seller_id = current_pubkey()
    or buyer_id = current_pubkey()
    or exists (
      select 1 from public.share_orders o
      join public.prediction_events e on o.event_id = e.id
      where o.id = order_id and e.creator_id = current_pubkey()
    )
  );
