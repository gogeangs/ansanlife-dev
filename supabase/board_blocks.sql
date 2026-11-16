-- 주민 이야기 IP 차단 (2026-11-17): 관리 페이지에서 '이 IP 차단' → 그 IP(해시)는 글·댓글·수정·신고 불가
-- board.sql 다음에 실행. 다시 실행해도 안전합니다(지우는 문장 없음).
create table if not exists public.board_blocks (
  ip_hash    text primary key,                 -- 글에 저장된 것과 같은 IP 해시 (전체 IP 는 모름)
  note       text not null default '' check (char_length(note) <= 200),   -- 차단 이유 (예: 글 12번 스팸)
  created_at timestamptz not null default now()
);
alter table public.board_blocks enable row level security;
revoke all on public.board_blocks from anon;
grant select, insert, delete on public.board_blocks to authenticated;
grant select, insert, update, delete on public.board_blocks to service_role;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'board_blocks' and policyname = 'board blocks: admin') then
    create policy "board blocks: admin" on public.board_blocks for all to authenticated using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;
