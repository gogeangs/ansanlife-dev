-- 안산살이 API(Edge Function) 보조 표 — schema.sql 다음에 실행. 다시 실행해도 안전합니다.
-- Edge Function 만 service_role 로 씁니다. 앱(anon)·관리자는 접근하지 않습니다.

-- 공지 번역 등 캐시 (Cloudflare KV 대신)
create table if not exists public.kv_cache (
  key        text primary key check (char_length(key) <= 200),
  value      jsonb not null,
  expires_at timestamptz not null
);
alter table public.kv_cache enable row level security;   -- 정책 없음 = anon/authenticated 접근 불가
revoke all on public.kv_cache from anon, authenticated;
create index if not exists kv_cache_exp_idx on public.kv_cache (expires_at);
-- 프로젝트를 'Automatically expose new tables' 끔으로 만들었으므로 service_role 권한을 직접 줌
grant select, insert, update, delete on public.kv_cache to service_role;

-- IP별 횟수 제한 (Cloudflare Rate Limiting 대신): 창(window) 안에서 limit 번까지 true
create table if not exists public.rate_hits (
  key          text primary key check (char_length(key) <= 200),
  window_start timestamptz not null,
  hits         integer not null
);
alter table public.rate_hits enable row level security;
revoke all on public.rate_hits from anon, authenticated;

create or replace function public.rate_hit(p_key text, p_limit integer, p_window_seconds integer)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  insert into public.rate_hits as r (key, window_start, hits) values (p_key, now(), 1)
  on conflict (key) do update
    set hits = case when r.window_start < now() - make_interval(secs => p_window_seconds) then 1 else r.hits + 1 end,
        window_start = case when r.window_start < now() - make_interval(secs => p_window_seconds) then now() else r.window_start end
  returning hits into n;
  return n <= p_limit;
end $$;
revoke all on function public.rate_hit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.rate_hit(text, integer, integer) to service_role;

-- 오래된 캐시·횟수 기록 정리 (가끔 실행하거나 pg_cron 으로)
create or replace function public.cleanup_edge_tables() returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.kv_cache where expires_at < now();
  delete from public.rate_hits where window_start < now() - interval '1 day';
$$;
revoke all on function public.cleanup_edge_tables() from public, anon, authenticated;
grant execute on function public.cleanup_edge_tables() to service_role;
