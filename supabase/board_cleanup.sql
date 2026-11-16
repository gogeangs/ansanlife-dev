-- 주민 이야기 보관 기간 (개인정보 처리방침 2026-11-17): board.sql · location_log.sql 다음에 실행. 다시 실행해도 안전합니다.
-- 글쓴이가 지운 글·댓글은 30일 뒤 완전히 삭제, 신고 기록은 1년 뒤 삭제. 매일 새벽 정리 작업(ansanlife-cleanup)에 더함
alter table public.board_posts add column if not exists deleted_at timestamptz;
alter table public.board_comments add column if not exists deleted_at timestamptz;
update public.board_posts set deleted_at = now() where deleted and deleted_at is null;
update public.board_comments set deleted_at = now() where deleted and deleted_at is null;

create or replace function public.cleanup_edge_tables() returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.kv_cache where expires_at < now();
  delete from public.rate_hits where window_start < now() - interval '1 day';
  delete from public.location_log where at < now() - interval '1 year';
  delete from public.board_comments where deleted and deleted_at < now() - interval '30 days';
  delete from public.board_posts where deleted and deleted_at < now() - interval '30 days';
  delete from public.board_reports where created_at < now() - interval '1 year';
$$;
revoke all on function public.cleanup_edge_tables() from public, anon, authenticated;
grant execute on function public.cleanup_edge_tables() to service_role;
