-- 안산살이 Supabase 운영 정리 (2026-11-15) — Security Advisor 경고 정리 + 자동 정리 예약. 다시 실행해도 안전합니다.

-- 1) 함수 search_path 고정 (Advisor: Function Search Path Mutable)
alter function public.touch_updated_at() set search_path = public, pg_temp;

-- 2) 관리자 확인 함수는 로그인한 사용자만 (관리자 정책은 모두 'to authenticated'라 anon 은 필요 없음)
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- 3) 프로젝트 생성 때 Supabase 가 만든 RLS 자동 켜기 함수: 이벤트 트리거로만 쓰이므로 API 로 부를 수 없게
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;

-- 4) 오래된 번역 캐시·접속 횟수 기록을 매일 새벽 3시 23분(KST)에 정리
create extension if not exists pg_cron;
select cron.unschedule(jobid) from cron.job where jobname = 'ansanlife-cleanup';
select cron.schedule('ansanlife-cleanup', '23 18 * * *', $$select public.cleanup_edge_tables()$$);  -- UTC 18:23 = KST 03:23

-- 남겨 둔 Advisor 항목 (의도된 설정)
--  - survey_responses 의 insert with check (true): 익명 설문 응답용. 열 길이·형식 제한은 표 제약으로 걸려 있음. 설문은 현재 꺼져 있음
--  - kv_cache·rate_hits 'RLS Enabled No Policy': API 서버(service_role)만 쓰는 표라 정책이 없는 것이 맞음
--  - Leaked Password Protection: Pro 요금제 기능
