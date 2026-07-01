-- Migration 2026-07-01: Contacts org-chart support
-- Adds two columns to kac_contacts:
--   reports_to  → the contact this person reports to (builds the org chart)
--   division    → free-text department/division label
-- Safe to run more than once (IF NOT EXISTS). Run in the Supabase SQL editor,
-- then hard-reload the app.

alter table kac_contacts
  add column if not exists reports_to uuid references kac_contacts(id) on delete set null;

alter table kac_contacts
  add column if not exists division text;

-- Verify (should list both new columns):
-- select column_name, data_type from information_schema.columns
-- where table_name = 'kac_contacts' and column_name in ('reports_to','division');
