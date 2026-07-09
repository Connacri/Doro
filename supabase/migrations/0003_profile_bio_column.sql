-- supabase/migrations/0003_profile_bio_column.sql
-- Deja appliquee sur rwzsnlfuqmfxouhfbeoi via MCP.
alter table public.profiles add column bio text not null default '';
