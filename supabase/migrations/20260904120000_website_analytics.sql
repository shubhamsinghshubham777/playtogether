-- Website Analytics: Visitors, Pageviews, and Downloads Tracking
-- Schema, RLS policies, indexes, and aggregation support for internal metrics.

-- 1. Website Visitors (deduplicated by visitor_id cookie)
create table if not exists public.website_visitors (
  visitor_id text primary key,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  pageviews_count int not null default 1 check (pageviews_count >= 1),
  first_referrer text,
  first_path text,
  user_agent text
);

-- 2. Website Pageviews (detailed log of each page navigation)
create table if not exists public.website_pageviews (
  id bigint generated always as identity primary key,
  visitor_id text not null references public.website_visitors (visitor_id) on delete cascade,
  pathname text not null,
  referrer text,
  created_at timestamptz not null default now()
);

-- 3. Website Downloads (direct installer downloads triggered via website)
create table if not exists public.website_downloads (
  id bigint generated always as identity primary key,
  visitor_id text,
  platform text not null check (platform in ('macos', 'windows', 'other')),
  release_version text,
  referrer text,
  user_agent text,
  created_at timestamptz not null default now()
);

-- Indexes for performance
create index if not exists website_visitors_last_seen_idx on public.website_visitors (last_seen_at desc);
create index if not exists website_visitors_first_seen_idx on public.website_visitors (first_seen_at desc);
create index if not exists website_pageviews_visitor_idx on public.website_pageviews (visitor_id);
create index if not exists website_pageviews_created_idx on public.website_pageviews (created_at desc);
create index if not exists website_pageviews_pathname_idx on public.website_pageviews (pathname);
create index if not exists website_downloads_created_idx on public.website_downloads (created_at desc);
create index if not exists website_downloads_platform_idx on public.website_downloads (platform);

-- Row Level Security (RLS)
alter table public.website_visitors enable row level security;
alter table public.website_pageviews enable row level security;
alter table public.website_downloads enable row level security;

-- Strictly revoke all public/anon/authenticated access — only service_role (internal server) can access
revoke all on public.website_visitors from public, anon, authenticated;
revoke all on public.website_pageviews from public, anon, authenticated;
revoke all on public.website_downloads from public, anon, authenticated;

grant all on public.website_visitors to service_role;
grant all on public.website_pageviews to service_role;
grant all on public.website_downloads to service_role;
