-- Migration 2026-06-30: Replace Acceptance Matrix product rows
-- New product list (10 items). Run once in the Supabase SQL editor. Safe to re-run.
-- NOTE: matrix cells are keyed by product row, so existing cell data for the OLD
--       products is cleared here — it cannot map onto a different product set.
--       Milestone columns and status options are left untouched.

begin;

-- 1) Remove cell data tied to the current product rows
delete from kac_matrix_data
where row_id in (select id from kac_matrix_config where config_type = 'row');

-- 2) Remove the current product rows
delete from kac_matrix_config where config_type = 'row';

-- 3) Insert the new product rows (in order)
insert into kac_matrix_config (config_type, label, sort_order) values
  ('row', 'Couplings',         0),
  ('row', 'Fittings',          1),
  ('row', 'Valves',            2),
  ('row', 'Suction Diffusers', 3),
  ('row', 'Pump Drops',        4),
  ('row', 'Mech Tees',         5),
  ('row', 'HDPE',              6),
  ('row', 'VBSS',              7),
  ('row', 'Tools',             8),
  ('row', 'Revit',             9);

commit;

-- Verify ----------------------------------------------------------------------
-- select label, sort_order from kac_matrix_config where config_type='row' order by sort_order;
