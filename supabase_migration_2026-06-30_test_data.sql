-- Migration 2026-06-30: Regenerate customer TEST DATA for the new matrix + sectors
-- Overwrites all acceptance-matrix cell data and all account key_sectors.
-- Tuned so OVERALL ACCEPTANCE (approved / eligible) lands around 60%.
-- Run AFTER the product-rows and sectors-v2 migrations. Run once in the Supabase SQL editor.
--
-- Acceptance math: per cell the status is weighted-random —
--   N/A 5%, Approved 57%, In Progress 18%, Not Started 12%, Rejected 8%
--   acceptance = approved / (total - N/A) = 0.57 / 0.95 ≈ 0.60  (≈60%)

begin;

-- 1) Wipe existing matrix cell data (the "acceptance criteria" values) -----------
delete from kac_matrix_data;

-- 2) Generate a fresh cell for every account × product × milestone --------------
insert into kac_matrix_data (id, account_id, row_id, col_id, status_id, updated_at)
select gen_random_uuid(),
       a.id,
       r.id,
       c.id,
       (select id from kac_matrix_config
          where config_type = 'status'
            and label = case
              when g.rnd < 0.05 then 'N/A'
              when g.rnd < 0.62 then 'Approved'
              when g.rnd < 0.80 then 'In Progress'
              when g.rnd < 0.92 then 'Not Started'
              else                    'Rejected'
            end
          limit 1),
       now() - (random() * interval '120 days')   -- spread changes over ~4 months
from kac_accounts a
cross join (select id from kac_matrix_config where config_type = 'row') r
cross join (select id from kac_matrix_config where config_type = 'col') c
cross join lateral (select random() as rnd) g;

-- 3) Reassign 1–2 of the new key sectors to every account -----------------------
update kac_accounts a
set key_sectors = (
      select string_agg(label, ', ' order by label)
      from (
        select label
        from kac_sectors
        where a.id is not null              -- force per-row (correlated) evaluation
        order by random()
        limit (1 + (abs(hashtext(a.id::text)) % 2))
      ) pick
    ),
    updated_at = now();

commit;

-- Verify ----------------------------------------------------------------------
-- Overall acceptance (should be ~60):
-- with cells as (
--   select s.label
--   from kac_matrix_data d
--   join kac_matrix_config s on s.id = d.status_id and s.config_type='status'
-- )
-- select round(100.0 * count(*) filter (where label='Approved')
--             / nullif(count(*) filter (where label <> 'N/A'),0), 1) as overall_acceptance_pct
-- from cells;
--
-- select distinct key_sectors from kac_accounts order by 1;
