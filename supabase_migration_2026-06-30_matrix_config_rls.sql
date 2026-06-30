-- Migration 2026-06-30: Ensure write access to kac_matrix_config
-- Fixes the Admin → Acceptance Matrix Config up/down arrows + add buttons not working.
-- Symptom cause: the table has RLS enabled but no INSERT/UPDATE/DELETE policy, so the
-- app's writes are silently rejected. This adds read + write policies for authenticated
-- users, mirroring kac_sectors. Run once in the Supabase SQL editor. Safe to re-run.

alter table kac_matrix_config enable row level security;

drop policy if exists "kac_matrix_config_read" on kac_matrix_config;
create policy "kac_matrix_config_read" on kac_matrix_config
  for select to authenticated using (true);

drop policy if exists "kac_matrix_config_write" on kac_matrix_config;
create policy "kac_matrix_config_write" on kac_matrix_config
  for all to authenticated using (true) with check (true);

-- After running, reload the app and try the arrows / + buttons again.
-- (If they still fail, open the browser console and click an arrow — the error text
--  will tell us whether it's a policy or a constraint issue.)
