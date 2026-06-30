-- Migration 2026-06-30 (v2): Update Key Sectors to the new 8 and remap account tags
-- New approved sectors: Commercial, Health, Industrial, Mining, Data Centres, Education, Government, Retail
-- Run once in the Supabase SQL editor. Safe to re-run (idempotent).
-- Pairs with the SECTORS constant (index.html).

begin;

-- 1) Reset the admin-managed sector list to the approved 8 ---------------------
delete from kac_sectors;
insert into kac_sectors (label, sort_order) values
  ('Commercial',   0),
  ('Health',       1),
  ('Industrial',   2),
  ('Mining',       3),
  ('Data Centres', 4),
  ('Education',    5),
  ('Government',   6),
  ('Retail',       7);

-- 2) Remap existing account sector tags onto the approved 8 --------------------
-- key_sectors is a comma-separated text field. Per account:
--   * "Data Centre" / "Data Centres" -> "Data Centres"
--   * keep Commercial / Health / Industrial / Mining / Education / Government / Retail
--   * drop every other (retired) tag, e.g. "Other"
--   * de-duplicate, re-join alphabetically (empty string if nothing remains)
update kac_accounts a
set key_sectors = sub.new_sectors,
    updated_at  = now()
from (
  select id,
         coalesce(string_agg(distinct mapped, ', ' order by mapped)
                  filter (where mapped is not null), '') as new_sectors
  from (
    select a2.id,
           case
             when btrim(s) ilike 'data centre%'                                              then 'Data Centres'
             when btrim(s) in ('Commercial','Health','Industrial','Mining','Education','Government','Retail') then btrim(s)
             else null
           end as mapped
    from kac_accounts a2
    cross join lateral unnest(string_to_array(coalesce(a2.key_sectors, ''), ',')) as s
  ) x
  group by id
) sub
where a.id = sub.id
  and coalesce(a.key_sectors, '') <> coalesce(sub.new_sectors, '');

commit;

-- Verify ----------------------------------------------------------------------
-- select label, sort_order from kac_sectors order by sort_order;
-- select distinct key_sectors from kac_accounts order by 1;
