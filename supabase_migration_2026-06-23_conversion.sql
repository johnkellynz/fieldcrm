-- ============================================================================
-- Field CRM — Migration 2026-06-23  ·  ACCOUNT CONVERSION HQ
-- Adds the editable fields the new "Conversion HQ" view writes to, ensures the
-- opportunities table exists in the cloud, and (PART B, OPTIONAL) switches the
-- app from single-user to a shared TEAM model so multiple reps can pull all
-- conversion data together.
--
-- Safe to re-run: every statement uses IF NOT EXISTS / idempotent policy drops.
--
-- HOW TO APPLY (simplest path — just run the whole file):
--   1. Open https://supabase.com/dashboard -> your project -> SQL Editor ->
--      click "+ New query".
--   2. Open this .sql file, Select All (Cmd-A), Copy, paste into the editor,
--      then click RUN. PART B (team sharing) and the CLEANUP block are
--      commented out, so a normal Run applies only PART A (columns +
--      opportunities table) and PART A.5 (sample data). Expect a green
--      "Success. No rows returned".
--   3. Reload the CRM (Cmd-R) and open Conversion HQ — it'll be populated and
--      the inline editors (must-have, invoice month, win %, rep) will save.
--
--   NOTE: the very first statement below makes this SQL session act as YOU
--   (looked up by email) so the seeded rows are owned by your account —
--   auth.uid() is null in the SQL Editor otherwise and the inserts would fail.
--   If your CRM login email is NOT mambashundo@gmail.com, change it there.
--   Later: uncomment & run PART B to enable team sharing; uncomment & run the
--   CLEANUP block at the bottom to remove the sample data.
-- ============================================================================


-- ============================================================================
-- PART A — Conversion fields + opportunities table  (SAFE, run anytime)
-- ============================================================================

-- ---- Make this SQL session act as YOU (so seeded rows get your user_id) -----
-- auth.uid() is null in the SQL Editor; this resolves it to your account for
-- the rest of the script. It sources your user id from the CRM data you
-- already own (your existing customers), falling back to the single auth user
-- — so it works without needing to know your login email. Does NOT alter any
-- saved RLS policy (those keep using auth.uid(), evaluated per-request).
do $$
declare uid text;
begin
  -- your user id, taken from data you already own (falls back to the one auth user)
  select coalesce(
    (select user_id::text from public.customers where user_id is not null order by created_at limit 1),
    (select id::text from auth.users order by created_at limit 1)
  ) into uid;
  if uid is null then
    raise exception 'Could not determine your user id — no rows in public.customers and no auth.users found.';
  end if;
  -- set both claim forms so auth.uid() resolves regardless of Supabase version
  perform set_config('request.jwt.claims', json_build_object('sub', uid)::text, false);
  perform set_config('request.jwt.claim.sub', uid, false);
end $$;

-- ---- customers: account-level conversion attributes ------------------------
alter table public.customers add column if not exists tier                 smallint;     -- 1 / 2 / 3
alter table public.customers add column if not exists conversion_stage     text;         -- identify / engage / demonstrate / convert / grow
alter table public.customers add column if not exists psa_tier             text;         -- current PSA: SILVER / GOLD / PLATINUM
alter table public.customers add column if not exists psa_target_tier      text;         -- target PSA tier
alter table public.customers add column if not exists share_of_wallet_pct  numeric;      -- estimated Victaulic share of this account's spend

-- ---- projects: must-have flag, market, penetration, invoice timing ---------
-- (projects.value already exists from the base schema)
alter table public.projects  add column if not exists must_have            boolean default false;
alter table public.projects  add column if not exists market               text;
alter table public.projects  add column if not exists sector               text;
alter table public.projects  add column if not exists penetration_pct      smallint;     -- manual override of the derived %
alter table public.projects  add column if not exists incumbent            text;         -- who we're displacing (weld / Gruvlok / press-fit)
alter table public.projects  add column if not exists expected_invoice_date date;        -- month this project is likely to invoice / land
alter table public.projects  add column if not exists probability          smallint;     -- 0-100 win probability
alter table public.projects  add column if not exists stage                text;         -- optional project conversion stage

-- ---- opportunities: create if missing, then add conversion columns ---------
-- This table backs the Opportunities view and the new Pipeline-by-month roll-up.
-- It was never in the original schema files, so create it here (idempotent).
create table if not exists public.opportunities (
  id                   bigserial primary key,
  user_id              uuid not null references auth.users(id) on delete cascade,
  customer_id          bigint references public.customers(id) on delete cascade,
  project_id           bigint references public.projects(id)  on delete set null,
  stage                text,
  expected_close_date  date,
  won_lost_reason      text,
  closed_at            timestamptz,
  created_at           timestamptz not null default now()
);
create index if not exists opportunities_user_idx     on public.opportunities(user_id);
create index if not exists opportunities_customer_idx on public.opportunities(customer_id);

-- new conversion columns on opportunities
alter table public.opportunities add column if not exists amount                numeric;   -- opportunity value (falls back to project.value)
alter table public.opportunities add column if not exists probability           smallint;  -- 0-100; otherwise inferred from stage
alter table public.opportunities add column if not exists expected_invoice_date date;      -- the month it lands when invoiced
alter table public.opportunities add column if not exists owner_name            text;      -- display owner for the multi-user pipeline roll-up

-- opportunities RLS — owner-only for now (PART B widens this to the team)
alter table public.opportunities enable row level security;
do $$
begin
  execute 'drop policy if exists "owner_select" on public.opportunities';
  execute 'drop policy if exists "owner_insert" on public.opportunities';
  execute 'drop policy if exists "owner_update" on public.opportunities';
  execute 'drop policy if exists "owner_delete" on public.opportunities';
  execute 'create policy "owner_select" on public.opportunities for select using (user_id = auth.uid())';
  execute 'create policy "owner_insert" on public.opportunities for insert with check (user_id = auth.uid())';
  execute 'create policy "owner_update" on public.opportunities for update using (user_id = auth.uid()) with check (user_id = auth.uid())';
  execute 'create policy "owner_delete" on public.opportunities for delete using (user_id = auth.uid())';
end$$;

-- ---- Seed the 8 Tier-1 national accounts (Australia) -----------------------
-- Creates a placeholder company "anchor" contact for each Tier-1 major so they
-- show up in segmentation / hit-list / funnel immediately. Owned by the user
-- who runs this. Skips any company you already have. Edit/merge later in-app.
insert into public.customers (user_id, name, company, country, category, region, importance, tier, conversion_stage, notes)
select auth.uid(), v.name, v.company, 'AU', 'Contractor T1', v.region, 3, 1, v.stage, v.note
from (values
  ('Watpac Mechanical / BGIS',           'Account anchor — Watpac/BGIS',        'QLD', 'demonstrate', 'Tier 1 seed. Status: Partial — deepen. Health/Defence/Gov, AUD $200M+.'),
  ('JCI / York Mechanical Services',     'Account anchor — JCI/York',           'NSW', 'identify',    'Tier 1 seed. Status: Low — target. Commercial/Industrial, AUD $180M+.'),
  ('Stowe Australia',                    'Account anchor — Stowe',              'QLD', 'demonstrate', 'Tier 1 seed. Status: Partial — grow. Multi-sector, AUD $150M+.'),
  ('Hastie Group / Ventia Mechanical',   'Account anchor — Hastie/Ventia',      'VIC', 'identify',    'Tier 1 seed. Status: Low — target. Health/Commercial, AUD $140M+.'),
  ('Mechanical One (Lendlease Services)','Account anchor — Mechanical One',     'NSW', 'convert',     'Tier 1 seed. Status: Active — protect & grow. Property/Retail/Gov, AUD $120M+.'),
  ('Nilsen (Electrical & Mechanical)',   'Account anchor — Nilsen',             'SA',  'identify',    'Tier 1 seed. Status: Low — target. Industrial/Mining, AUD $100M+.'),
  ('AE Smith',                           'Account anchor — AE Smith',           'VIC', 'grow',        'Tier 1 seed. Status: Active — grow wallet. Commercial/Health, AUD $90M+.'),
  ('Intech Engineers',                   'Account anchor — Intech',             'WA',  'engage',      'Tier 1 seed. Status: Emerging — engage. Resources/Industrial, AUD $80M+.')
) as v(company, name, region, stage, note)
where not exists (
  select 1 from public.customers c
  where c.user_id = auth.uid() and lower(c.company) = lower(v.company)
);

-- ---- Seed the New Zealand Tier-1 targets (modelled — confirm later) ---------
insert into public.customers (user_id, name, company, country, category, region, importance, tier, conversion_stage, notes)
select auth.uid(), v.name, v.company, 'NZ', 'Contractor T1', v.region, 3, 1, 'identify', v.note
from (values
  ('Aquaheat New Zealand', 'Account anchor — Aquaheat',  'Auckland',     'NZ Tier 1 (modelled). NZ largest mechanical contractor, 350+ staff. Commercial/Health/Digital/Mission-critical.'),
  ('Economech',            'Account anchor — Economech', 'Auckland',     'NZ Tier 1 (modelled). Commercial + data centres (Aotea Centre, Auckland Town Hall).'),
  ('Chilltech',            'Account anchor — Chilltech', 'Auckland',     'NZ Tier 1 (modelled). 60+ staff, upper North Island commercial/retail.'),
  ('Thermal Solutions',    'Account anchor — Thermal Sol','Auckland',    'NZ Tier 1 (modelled). Industrial/cold chain/food & bev (Fonterra). Auckland/Hastings/Chch.'),
  ('AMT Group',            'Account anchor — AMT Group', 'Christchurch', 'NZ Tier 1 (modelled). Commercial/health, Christchurch/national.')
) as v(company, name, region, note)
where not exists (
  select 1 from public.customers c
  where c.user_id = auth.uid() and lower(c.company) = lower(v.company)
);

-- Verify PART A:
-- select column_name from information_schema.columns
--   where table_schema='public' and table_name='projects' and column_name='must_have';
-- select company, tier, conversion_stage from public.customers where tier = 1 order by country, company;


-- ============================================================================
-- PART A.5 — SAMPLE DATA  (OPTIONAL · so the Conversion HQ populates instantly)
-- ----------------------------------------------------------------------------
-- Adds ~10 must-have projects (spanning 2026 / 2027 / 2028+), matching
-- opportunities, and a little acceptance data so the value-by-year table,
-- penetration bars and pipeline all show real numbers. Each links to the
-- Tier-1 accounts seeded in PART A. Idempotent. Remove anytime with the
-- CLEANUP block at the very bottom of this file.
-- Run PART A first (the accounts must exist).
-- ============================================================================

-- ---- Sample must-have projects ---------------------------------------------
insert into public.projects (user_id, name, status, customer_ids, value, must_have, expected_invoice_date, probability, market, sector)
select auth.uid(), v.name, v.status,
  array(select id from public.customers c where c.user_id = auth.uid() and lower(c.company) = lower(v.company) limit 1),
  v.value, true, v.inv::date, v.prob, v.market, v.sector
from (values
  ('Footscray Hospital — Mechanical Services', 'In-build', 'AE Smith',                            1800000, '2026-09-01', 70, 'Building Svces', 'Health'),
  ('Western Sydney Hyperscale DC (WS3)',       'Tender',   'Mechanical One (Lendlease Services)',  3200000, '2026-11-01', 60, 'Data Centre',    'Mission-critical'),
  ('Perth Resources Process Facility',         'Lead',     'Intech Engineers',                     900000,  '2026-06-01', 55, 'Mining',         'Resources'),
  ('Auckland City Hospital — Plant Upgrade',   'In-build', 'Economech',                            1200000, '2026-10-01', 50, 'Building Svces', 'Health'),
  ('Sydney CBD Commercial Tower',              'Lead',     'JCI / York Mechanical Services',       1600000, '2027-01-01', 40, 'Building Svces', 'Commercial'),
  ('Brisbane Live Precinct — Tower B',         'Tender',   'Stowe Australia',                      1400000, '2027-03-01', 45, 'Building Svces', 'Commercial'),
  ('Datagrid Invercargill — AI Factory',       'Tender',   'Aquaheat New Zealand',                 4000000, '2027-05-01', 40, 'Data Centre',    'Mission-critical'),
  ('Melbourne Big Build — New Hospital',       'Lead',     'Hastie Group / Ventia Mechanical',     2100000, '2027-07-01', 40, 'Building Svces', 'Health'),
  ('Adelaide Industrial Cold Store',           'Tender',   'Nilsen (Electrical & Mechanical)',     700000,  '2027-10-01', 50, 'Industrial',     'Cold chain'),
  ('QLD Defence Facility — Stage 1',           'Lead',     'Watpac Mechanical / BGIS',             2600000, '2028-02-01', 35, 'Infrastructure', 'Defence')
) as v(name, status, company, value, inv, prob, market, sector)
where exists (select 1 from public.customers c where c.user_id = auth.uid() and lower(c.company) = lower(v.company))
  and not exists (select 1 from public.projects p where p.user_id = auth.uid() and p.name = v.name);

-- ---- Sample opportunities (feed the Pipeline-by-month tab) ------------------
-- owner_name spreads across a few reps so the per-rep roll-up is meaningful.
-- All editable inline in the Pipeline tab (owner / month / amount / win %).
-- NOTE: this opportunities table pre-existed with a required "name" column and
-- uses "value" (not "amount") for the dollar figure — so we populate both here.
insert into public.opportunities (user_id, name, customer_id, project_id, stage, expected_close_date, expected_invoice_date, value, probability, owner_name)
select auth.uid(), v.proj,
  (select id from public.customers c where c.user_id = auth.uid() and lower(c.company) = lower(v.company) limit 1),
  (select id from public.projects p where p.user_id = auth.uid() and p.name = v.proj limit 1),
  v.stage, v.dt::date, v.dt::date, v.amount, v.prob, v.owner
from (values
  ('AE Smith',                           'Footscray Hospital — Mechanical Services', 'convert',     '2026-09-01', 1800000, 70, 'JK'),
  ('Mechanical One (Lendlease Services)','Western Sydney Hyperscale DC (WS3)',       'demonstrate', '2026-11-01', 3200000, 60, 'Sarah M'),
  ('Intech Engineers',                   'Perth Resources Process Facility',         'demonstrate', '2026-06-01', 900000,  55, 'Dave R'),
  ('Economech',                          'Auckland City Hospital — Plant Upgrade',   'convert',     '2026-10-01', 1200000, 50, 'Mere T'),
  ('Stowe Australia',                    'Brisbane Live Precinct — Tower B',         'demonstrate', '2027-03-01', 1400000, 45, 'Sarah M'),
  ('Aquaheat New Zealand',               'Datagrid Invercargill — AI Factory',       'engage',      '2027-05-01', 4000000, 40, 'Mere T'),
  ('JCI / York Mechanical Services',     'Sydney CBD Commercial Tower',              'engage',      '2027-01-01', 1600000, 40, 'JK'),
  ('Hastie Group / Ventia Mechanical',   'Melbourne Big Build — New Hospital',       'demonstrate', '2027-07-01', 2100000, 40, 'Dave R')
) as v(company, proj, stage, dt, amount, prob, owner)
where exists (select 1 from public.projects p where p.user_id = auth.uid() and p.name = v.proj)
  and not exists (
    select 1 from public.opportunities o join public.projects p on p.id = o.project_id
    where o.user_id = auth.uid() and p.name = v.proj);

-- ---- Sample acceptance (drives Victaulic penetration % on key accounts) -----
-- Attaches a few product statuses to the anchor contact of each company, using
-- the user's existing products ranked by sort_order (prod 1, 2, 3 ...).
with prod as (
  select id, row_number() over (order by sort_order, id) as rn
  from public.products where user_id = auth.uid()
), cust as (
  select id, company, row_number() over (partition by lower(company) order by id) as rn
  from public.customers where user_id = auth.uid()
)
insert into public.acceptance (user_id, customer_id, product_id, status)
select auth.uid(), cu.id, pr.id, s.status
from (values
  ('AE Smith',                            1, 'approved'),
  ('AE Smith',                            2, 'specified'),
  ('AE Smith',                            3, 'in_progress'),
  ('Mechanical One (Lendlease Services)', 1, 'approved'),
  ('Mechanical One (Lendlease Services)', 2, 'approved'),
  ('Economech',                           1, 'approved'),
  ('Economech',                           2, 'specified'),
  ('Stowe Australia',                     1, 'in_progress'),
  ('Aquaheat New Zealand',                1, 'specified')
) as s(company, prodrank, status)
join cust cu on lower(cu.company) = lower(s.company) and cu.rn = 1
join prod pr on pr.rn = s.prodrank
where not exists (
  select 1 from public.acceptance a
  where a.user_id = auth.uid() and a.customer_id = cu.id and a.product_id = pr.id);

-- Verify A.5:  select name, value, expected_invoice_date, probability from public.projects where must_have order by expected_invoice_date;


-- ============================================================================
-- PART B — TEAM SHARING (OPTIONAL · SECURITY-SENSITIVE · read before running)
-- ----------------------------------------------------------------------------
-- WHAT THIS DOES: replaces the "each user only sees their own rows" policies
-- with "any signed-in user sees and edits ALL rows". This is what makes
-- "multiple users pulling all conversion data together" work — every rep's
-- accounts, projects and opportunities roll up into one shared pipeline.
--
-- IMPLICATION: there is no per-rep privacy after this. Everyone with a login
-- sees everything (this matches your playbook decision: "account sharing fully
-- open across reps"). user_id is still recorded on every row for the audit
-- trail and for owner attribution in the pipeline view.
--
-- Run this ONLY when you have created the other users' logins and are ready to
-- share. To undo, re-run PART A's owner-only policy block per table.
-- ============================================================================

-- Uncomment the whole block below to enable team sharing:
/*
do $$
declare t text;
begin
  foreach t in array array['customers','interactions','projects','products','acceptance','history','lunch_learns','opportunities']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "owner_select" on public.%I', t);
    execute format('drop policy if exists "owner_insert" on public.%I', t);
    execute format('drop policy if exists "owner_update" on public.%I', t);
    execute format('drop policy if exists "owner_delete" on public.%I', t);
    execute format('drop policy if exists "team_select" on public.%I', t);
    execute format('drop policy if exists "team_insert" on public.%I', t);
    execute format('drop policy if exists "team_update" on public.%I', t);
    execute format('drop policy if exists "team_delete" on public.%I', t);
    -- any authenticated user can read every row
    execute format('create policy "team_select" on public.%I for select using (auth.role() = ''authenticated'')', t);
    -- inserts must still stamp the creator (preserves the audit trail)
    execute format('create policy "team_insert" on public.%I for insert with check (user_id = auth.uid())', t);
    -- any authenticated user can update / delete any row (fully open team)
    execute format('create policy "team_update" on public.%I for update using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t);
    execute format('create policy "team_delete" on public.%I for delete using (auth.role() = ''authenticated'')', t);
  end loop;
end$$;
*/

-- After enabling PART B, set owner_name on opportunities so the pipeline-by-
-- owner table reads nicely across users, e.g.:
--   update public.opportunities set owner_name = 'JK' where user_id = auth.uid() and owner_name is null;


-- ============================================================================
-- CLEANUP — remove the PART A.5 sample data (run only if you want it gone)
-- ----------------------------------------------------------------------------
-- Deletes the sample opportunities, projects and acceptance added above.
-- The seeded Tier-1 "Account anchor —" contacts are left in place (they are
-- useful real accounts); delete those manually if you don't want them.
-- Uncomment to run:
/*
delete from public.opportunities
  where user_id = auth.uid()
    and project_id in (
      select id from public.projects where user_id = auth.uid() and name = any (array[
        'Footscray Hospital — Mechanical Services','Western Sydney Hyperscale DC (WS3)',
        'Perth Resources Process Facility','Auckland City Hospital — Plant Upgrade',
        'Sydney CBD Commercial Tower','Brisbane Live Precinct — Tower B',
        'Datagrid Invercargill — AI Factory','Melbourne Big Build — New Hospital',
        'Adelaide Industrial Cold Store','QLD Defence Facility — Stage 1']));

delete from public.projects
  where user_id = auth.uid() and name = any (array[
    'Footscray Hospital — Mechanical Services','Western Sydney Hyperscale DC (WS3)',
    'Perth Resources Process Facility','Auckland City Hospital — Plant Upgrade',
    'Sydney CBD Commercial Tower','Brisbane Live Precinct — Tower B',
    'Datagrid Invercargill — AI Factory','Melbourne Big Build — New Hospital',
    'Adelaide Industrial Cold Store','QLD Defence Facility — Stage 1']);

-- (optional) clear the sample acceptance from the anchor contacts:
-- delete from public.acceptance a using public.customers c
--   where a.user_id = auth.uid() and a.customer_id = c.id
--     and c.company in ('AE Smith','Mechanical One (Lendlease Services)','Economech',
--                       'Stowe Australia','Aquaheat New Zealand');
*/
