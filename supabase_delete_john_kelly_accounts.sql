-- Delete ALL accounts assigned to John Kelly (john.kelly@victaulic.com)
-- ---------------------------------------------------------------------------
-- Removes every account where assigned_to = John Kelly, plus all of their child
-- records (matrix cells, checklist, notes, activities, contacts). Irreversible.
-- Other people's accounts and all team/config data are untouched.
-- Run in the Supabase SQL editor.

-- STEP 1 (optional) — preview what will be deleted BEFORE running the delete:
-- select company_name, current_stage, estimated_revenue
-- from kac_accounts
-- where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com')
-- order by company_name;

-- STEP 2 — delete. Wrapped in a transaction: if anything errors, nothing is removed.
begin;

-- Child rows first (explicit — safe whether or not each FK cascades on delete)
delete from kac_matrix_data where account_id in (
  select id from kac_accounts where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com'));
delete from kac_checklist where account_id in (
  select id from kac_accounts where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com'));
delete from kac_notes where account_id in (
  select id from kac_accounts where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com'));
delete from kac_activities where account_id in (
  select id from kac_accounts where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com'));
delete from kac_contacts where account_id in (
  select id from kac_accounts where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com'));

-- Then the accounts themselves
delete from kac_accounts
where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com');

commit;

-- Verify none remain (expect 0):
-- select count(*) from kac_accounts
-- where assigned_to = (select id from auth.users where email = 'john.kelly@victaulic.com');
