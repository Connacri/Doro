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
