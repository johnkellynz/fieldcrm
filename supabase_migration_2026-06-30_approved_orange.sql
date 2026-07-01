-- Migration 2026-06-30: Make the "Approved" status orange (brand colour)
-- s.color drives the status boxes AND the matrix grid cells, so this updates both.
-- Run once in the Supabase SQL editor, then hard-reload.

update kac_matrix_config
set color = '#F58220'
where config_type = 'status' and label = 'Accepted';
