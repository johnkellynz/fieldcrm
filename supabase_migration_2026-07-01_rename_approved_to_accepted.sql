-- Migration 2026-07-01: Rename the "Approved" product-line status to "Accepted"
--
-- Renames the status label in kac_matrix_config. The app code (index.html),
-- dashboards, and PDF exports were updated in the same change to key off 'Accepted'.
-- Cell history in kac_matrix_data references the status by id (not label), so
-- existing data needs no migration and is unaffected by this rename.

update kac_matrix_config
set label = 'Accepted'
where config_type = 'status'
  and label = 'Approved';

-- Verify:
-- select id, label, color, sort_order
-- from kac_matrix_config
-- where config_type = 'status'
-- order by sort_order;
