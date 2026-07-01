-- Migration 2026-06-30 (v2): Regenerate Acceptance test data — varied, capped at 90%
-- Supersedes supabase_migration_2026-06-30_test_data.sql.
-- Goals: every account gets data (>50 customers), per-customer acceptance VARIES
--        roughly 25%–90%, and NO customer reaches 100%.
--
-- How: each account gets a stable target acceptance p in [0.25, 0.90] derived from a
-- hash of its id (so it's the same across all its cells, and varies account to account).
-- Per cell: 4% N/A; of the rest, Approved with probability p; the remainder split across
-- In Progress / Not Started / Rejected. acceptance = approved / eligible ≈ p.
--
-- Run once in the Supabase SQL editor. Run AFTER the product-rows migration.

begin;

-- Wipe existing cell data
delete from kac_matrix_data;

-- Regenerate for every account × product × milestone
insert into kac_matrix_data (id, account_id, row_id, col_id, status_id, updated_at, updated_by)
select gen_random_uuid(), a.id, r.id, c.id,
  case
    when g.r1 < 0.04
      then (select id from kac_matrix_config where config_type='status' and label='N/A'          limit 1)
    when g.r2 < (0.25 + (abs(hashtext(a.id::text)) % 1000) / 1000.0 * 0.65)
      then (select id from kac_matrix_config where config_type='status' and label='Accepted'     limit 1)
    when g.r3 < 0.50
      then (select id from kac_matrix_config where config_type='status' and label='In Progress'  limit 1)
    when g.r3 < 0.80
      then (select id from kac_matrix_config where config_type='status' and label='Not Started'  limit 1)
    else     (select id from kac_matrix_config where config_type='status' and label='Rejected'    limit 1)
  end,
  now() - (random() * interval '150 days'),
  (select id from profiles limit 1)            -- satisfies updated_by if NOT NULL
from kac_accounts a
cross join (select id from kac_matrix_config where config_type='row') r
cross join (select id from kac_matrix_config where config_type='col') c
cross join lateral (select random() as r1, random() as r2, random() as r3) g;

commit;

-- Verify ----------------------------------------------------------------------
-- Per-customer acceptance spread (should range ~25–90, none at 100):
-- with cell as (
--   select d.account_id,
--          count(*) filter (where s.label='Accepted') as appr,
--          count(*) filter (where s.label <> 'N/A')   as elig
--   from kac_matrix_data d
--   join kac_matrix_config s on s.id = d.status_id and s.config_type='status'
--   group by d.account_id)
-- select round(100.0*appr/nullif(elig,0)) as pct, count(*) accounts
-- from cell group by 1 order by 1;
