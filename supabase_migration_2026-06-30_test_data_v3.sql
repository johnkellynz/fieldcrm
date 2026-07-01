-- Migration 2026-06-30 (v3): Acceptance test data — deterministic, varied, capped at 90%
-- Supersedes test_data v1/v2. v2 relied on random() in a LATERAL, which collapsed to a
-- near-constant on some Postgres setups (everything ended up Approved → ~100%). This version
-- is fully DETERMINISTIC via hashtext, so every cell varies and per-account acceptance
-- lands between ~25% and ~90% (never 100%).
--
--   per-account target p = 0.25 + hash(id)%1000/1000 * 0.65   →  [0.25, 0.90]
--   per cell: 4% N/A; of the rest, Approved when hash<p; else In Progress / Not Started / Rejected
--   acceptance = approved / eligible ≈ p
--
-- Run once in the Supabase SQL editor, AFTER the product-rows migration.

begin;

delete from kac_matrix_data;

insert into kac_matrix_data (id, account_id, row_id, col_id, status_id, updated_at, updated_by)
select gen_random_uuid(), a.id, r.id, c.id,
  case
    when (abs(hashtext(a.id::text||r.id::text||c.id::text||'na')) % 10000)/10000.0 < 0.04
      then (select id from kac_matrix_config where config_type='status' and label='N/A'          limit 1)
    when (abs(hashtext(a.id::text||r.id::text||c.id::text||'ap')) % 10000)/10000.0
         < (0.25 + (abs(hashtext(a.id::text)) % 1000)/1000.0 * 0.65)
      then (select id from kac_matrix_config where config_type='status' and label='Accepted'     limit 1)
    when (abs(hashtext(a.id::text||r.id::text||c.id::text||'sp')) % 10000)/10000.0 < 0.50
      then (select id from kac_matrix_config where config_type='status' and label='In Progress'  limit 1)
    when (abs(hashtext(a.id::text||r.id::text||c.id::text||'sp')) % 10000)/10000.0 < 0.80
      then (select id from kac_matrix_config where config_type='status' and label='Not Started'  limit 1)
    else     (select id from kac_matrix_config where config_type='status' and label='Rejected'    limit 1)
  end,
  now() - ((abs(hashtext(a.id::text||r.id::text||c.id::text||'dt')) % 150) || ' days')::interval,
  (select id from profiles limit 1)
from kac_accounts a
cross join (select id from kac_matrix_config where config_type='row') r
cross join (select id from kac_matrix_config where config_type='col') c;

commit;

-- Verify: spread of per-customer acceptance (expect ~25–90, none at 100) ----------
-- with cell as (
--   select d.account_id,
--          count(*) filter (where s.label='Accepted') a,
--          count(*) filter (where s.label<>'N/A')     e
--   from kac_matrix_data d
--   join kac_matrix_config s on s.id=d.status_id and s.config_type='status'
--   group by d.account_id)
-- select round(100.0*a/nullif(e,0)) pct, count(*) accounts from cell group by 1 order by 1;
