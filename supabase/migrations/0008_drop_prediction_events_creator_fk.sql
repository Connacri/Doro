-- Drop FK constraint linking creator_id to profiles.public_key
-- Les creator_id sont des adresses wallet (0x<clé_ed25519>) qui ne
-- correspondent pas aux public_key stockées dans profiles (identité nœud).
alter table public.prediction_events drop constraint if exists prediction_events_creator_id_fkey;
