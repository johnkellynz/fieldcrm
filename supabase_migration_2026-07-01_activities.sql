-- Migration 2026-07-01: Contact activity logging
-- New table kac_activities — one row per logged interaction a rep has with a contact.
-- Feeds the per-rep Activity summary on the dashboard.
-- Run once in the Supabase SQL editor, then hard-reload the app.

create table if not exists kac_activities (
  id            uuid primary key,
  account_id    uuid references kac_accounts(id) on delete cascade,
  contact_id    uuid references kac_contacts(id) on delete set null,
  user_id       uuid,
  activity_type text,
  note          text,
  created_at    timestamptz default now()
);

create index if not exists kac_activities_account_idx on kac_activities(account_id);
create index if not exists kac_activities_user_idx    on kac_activities(user_id);
create index if not exists kac_activities_created_idx  on kac_activities(created_at);

-- Team CRM: any signed-in user can read/write activity (managers need the full picture).
alter table kac_activities enable row level security;

drop policy if exists kac_activities_all_authenticated on kac_activities;
create policy kac_activities_all_authenticated on kac_activities
  for all to authenticated using (true) with check (true);

-- Verify:
-- select count(*) from kac_activities;
