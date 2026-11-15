-- 위치정보 이용·제공사실 확인자료 (위치정보의 보호 및 이용 등에 관한 법률 제16조 제2항)
-- API 서버가 위치를 쓴 순간 자동 기록. 좌표·IP·기기 정보는 남기지 않음(익명 서비스). 1년 보존 후 자동 삭제(법정 6개월 이상)
-- 다시 실행해도 안전합니다.
create table if not exists public.location_log (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  service   text not null check (service in ('bus', 'hospital', 'pharmacy')),
  provided_to text not null default '제3자 제공 없음'
);
alter table public.location_log enable row level security;   -- 정책 없음 = anon/authenticated 접근 불가
revoke all on public.location_log from anon, authenticated;
grant select, insert, delete on public.location_log to service_role;
create index if not exists location_log_at_idx on public.location_log (at);

-- 매일 정리 작업에 1년 지난 기록 삭제 추가
create or replace function public.cleanup_edge_tables() returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.kv_cache where expires_at < now();
  delete from public.rate_hits where window_start < now() - interval '1 day';
  delete from public.location_log where at < now() - interval '1 year';
$$;
revoke all on function public.cleanup_edge_tables() from public, anon, authenticated;
grant execute on function public.cleanup_edge_tables() to service_role;
