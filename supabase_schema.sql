-- ============================================================================
-- Field CRM — Postgres schema
-- Mirrors the Dexie v3 schema (customers, interactions, projects, products,
-- acceptance, history) with user_id columns and Row-Level Security.
-- Run this once in Supabase SQL Editor (https://supabase.com/dashboard → SQL Editor).
-- Safe to re-run: uses IF NOT EXISTS and re-creates RLS policies idempotently.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------

create table if not exists public.customers (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  title            text,
  company          text,
  region           text,
  country          text,
  email            text,
  phone            text,
  address          text,
  lat              double precision,
  lng              double precision,
  importance       smallint default 2,
  reports_to       bigint references public.customers(id) on delete set null,
  category         text,
  likes            text[] default '{}',
  dislikes         text[] default '{}',
  notes            text,
  last_contact_at  timestamptz,
  -- Tracks per-contact adoption of Victaulic tools and prior training.
  -- Yes / No / Unknown (text, mirroring lunch_learns.uses_revit_toolbar).
  uses_revit_toolbar text,
  attended_training  text,
  created_at       timestamptz not null default now()
);
create index if not exists customers_user_idx        on public.customers(user_id);
create index if not exists customers_user_region_idx on public.customers(user_id, region);
create index if not exists customers_company_idx     on public.customers(user_id, company);

-- Idempotent column adds for existing Supabase projects (re-run safe).
alter table public.customers add column if not exists uses_revit_toolbar text;
alter table public.customers add column if not exists attended_training  text;

create table if not exists public.interactions (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  customer_id      bigint not null references public.customers(id) on delete cascade,
  type             text,
  date             date,
  note             text,
  action           text,
  action_due_date  date,
  action_done      boolean default false,
  created_at       timestamptz not null default now()
);
create index if not exists interactions_user_idx     on public.interactions(user_id);
create index if not exists interactions_customer_idx on public.interactions(customer_id);
create index if not exists interactions_due_idx      on public.interactions(user_id, action_due_date)
  where action_done = false;

create table if not exists public.projects (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  status           text,
  customer_ids     bigint[] default '{}',
  lat              double precision,
  lng              double precision,
  value            numeric,
  created_at       timestamptz not null default now()
);
create index if not exists projects_user_idx on public.projects(user_id);

create table if not exists public.products (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  sort_order       integer default 0,
  created_at       timestamptz not null default now()
);
create index if not exists products_user_idx on public.products(user_id);

create table if not exists public.acceptance (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  customer_id      bigint not null references public.customers(id) on delete cascade,
  product_id       bigint not null references public.products(id)  on delete cascade,
  status           text not null default 'not_engaged',
  notes            text,
  updated_at       timestamptz not null default now(),
  unique (customer_id, product_id)
);
create index if not exists acceptance_user_idx   on public.acceptance(user_id);
create index if not exists acceptance_status_idx on public.acceptance(user_id, status);

create table if not exists public.history (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  customer_id      bigint not null references public.customers(id) on delete cascade,
  product_id       bigint not null references public.products(id)  on delete cascade,
  prev_status      text,
  new_status       text,
  changed_at       timestamptz not null default now()
);
create index if not exists history_user_idx     on public.history(user_id);
create index if not exists history_customer_idx on public.history(customer_id);
create index if not exists history_window_idx   on public.history(user_id, changed_at desc);

create table if not exists public.lunch_learns (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  company          text not null,
  topics           text,
  date             date not null,
  notes            text,
  attendee_ids     bigint[] default '{}',
  created_at       timestamptz not null default now()
);
create index if not exists lunch_learns_user_idx    on public.lunch_learns(user_id);
create index if not exists lunch_learns_date_idx    on public.lunch_learns(user_id, date desc);
create index if not exists lunch_learns_company_idx on public.lunch_learns(user_id, company);

-- ----------------------------------------------------------------------------
-- Row-Level Security
-- A user can read/write only their own rows. The publishable key on its own
-- gives no access until a session exists and matches user_id.
-- ----------------------------------------------------------------------------

alter table public.customers    enable row level security;
alter table public.interactions enable row level security;
alter table public.projects     enable row level security;
alter table public.products     enable row level security;
alter table public.acceptance   enable row level security;
alter table public.history      enable row level security;
alter table public.lunch_learns enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['customers','interactions','projects','products','acceptance','history','lunch_learns']
  loop
    execute format('drop policy if exists "owner_select" on public.%I', t);
    execute format('drop policy if exists "owner_insert" on public.%I', t);
    execute format('drop policy if exists "owner_update" on public.%I', t);
    execute format('drop policy if exists "owner_delete" on public.%I', t);

    execute format('create policy "owner_select" on public.%I for select using (user_id = auth.uid())', t);
    execute format('create policy "owner_insert" on public.%I for insert with check (user_id = auth.uid())', t);
    execute format('create policy "owner_update" on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    execute format('create policy "owner_delete" on public.%I for delete using (user_id = auth.uid())', t);
  end loop;
end$$;

-- ----------------------------------------------------------------------------
-- Quick smoke test — uncomment to verify after running:
-- select tablename from pg_tables where schemaname = 'public' order by tablename;
-- ----------------------------------------------------------------------------
