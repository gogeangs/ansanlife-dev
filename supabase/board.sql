-- 안산살이 주민 이야기 (2026-11-16): 같은 시·군 사람끼리 쓰는 게시판.
-- 가입 없이 닉네임 + 비밀번호(해시로만 저장)로 글·댓글을 쓰고, IP 는 앞 두 자리만 공개.
-- 앱(anon)은 이 표들을 직접 읽거나 쓰지 못하고, API 서버(Edge Function, service key)만 씀. 관리자는 대시보드·관리 페이지에서 조회·숨김.
-- schema.sql · admin.sql 다음에 SQL Editor 에서 실행. 다시 실행해도 안전합니다.

create table if not exists public.board_posts (
  id            bigint generated always as identity primary key,
  region        text not null check (char_length(region) between 2 and 40),   -- '경기도 안산시' · '서울특별시'
  nick          text not null check (char_length(nick) between 2 and 12),
  pw_hash       text not null,                       -- PBKDF2 (원래 비밀번호는 저장 안 함)
  ip_mask       text not null default '?',          -- 공개되는 앞 두 자리 (예: 211.234)
  ip_hash       text not null default '',           -- 같은 IP 확인용 (전체 IP 는 저장 안 함)
  country       text not null default 'en',         -- 글쓴이가 고른 나라 (국기 표시)
  lang          text not null default 'ko',         -- 쓸 때 앱 언어 (같은 언어 사용자에게는 번역 안 함)
  title         text not null check (char_length(title) between 1 and 60),
  body          text not null check (char_length(body) between 1 and 2000),
  comment_count integer not null default 0,
  report_count  integer not null default 0,
  hidden        boolean not null default false,     -- 신고 누적·글쓴이 삭제·운영자 숨김
  deleted       boolean not null default false,     -- 글쓴이가 지움
  created_at    timestamptz not null default now(),
  edited_at     timestamptz                         -- 글쓴이가 고친 시각 (고친 적 없으면 null)
);
alter table public.board_posts add column if not exists edited_at timestamptz;   -- 이미 만든 표에도 추가
create index if not exists board_posts_region_idx on public.board_posts (region, id desc) where not hidden;

create table if not exists public.board_comments (
  id           bigint generated always as identity primary key,
  post_id      bigint not null references public.board_posts (id) on delete cascade,
  nick         text not null check (char_length(nick) between 2 and 12),
  pw_hash      text not null,
  ip_mask      text not null default '?',
  ip_hash      text not null default '',
  country      text not null default 'en',
  lang         text not null default 'ko',
  body         text not null check (char_length(body) between 1 and 500),
  report_count integer not null default 0,
  hidden       boolean not null default false,
  deleted      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists board_comments_post_idx on public.board_comments (post_id, id);

create table if not exists public.board_reports (
  target     text not null check (target in ('post', 'comment')),
  target_id  bigint not null,
  ip_hash    text not null,
  created_at timestamptz not null default now(),
  primary key (target, target_id, ip_hash)          -- 같은 IP 는 한 번만
);

-- 댓글 수 자동 갱신 (숨김·삭제된 댓글은 빼고 셈)
create or replace function public.board_sync_count() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare pid bigint := coalesce(new.post_id, old.post_id);
begin
  update public.board_posts set comment_count = (select count(*) from public.board_comments where post_id = pid and not hidden) where id = pid;
  return null;
end $$;
drop trigger if exists board_comments_count on public.board_comments;
create trigger board_comments_count after insert or update of hidden or delete on public.board_comments for each row execute function public.board_sync_count();

-- 신고 수 다시 세고, 기준 이상이면 숨김 (API 서버가 부름)
create or replace function public.board_report_count(p_target text, p_id bigint, p_hide_at integer) returns void
  language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  select count(*) into n from public.board_reports where target = p_target and target_id = p_id;
  if p_target = 'post' then
    update public.board_posts set report_count = n, hidden = hidden or n >= p_hide_at where id = p_id;
  else
    update public.board_comments set report_count = n, hidden = hidden or n >= p_hide_at where id = p_id;
  end if;
end $$;
revoke all on function public.board_report_count(text, bigint, integer) from public, anon, authenticated;

alter table public.board_posts enable row level security;
alter table public.board_comments enable row level security;
alter table public.board_reports enable row level security;
revoke all on public.board_posts, public.board_comments, public.board_reports from anon;
-- anon 정책 없음 = 앱이 직접 접근 불가. 관리자만 조회·숨김 처리
grant select, update, delete on public.board_posts, public.board_comments to authenticated;
grant select on public.board_reports to authenticated;
drop policy if exists "board posts: admin" on public.board_posts;
create policy "board posts: admin" on public.board_posts for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "board comments: admin" on public.board_comments;
create policy "board comments: admin" on public.board_comments for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "board reports: admin" on public.board_reports;
create policy "board reports: admin" on public.board_reports for select to authenticated using (public.is_admin());

-- API 서버(service_role)만 읽고 씀. 이 프로젝트는 새 표에 service_role 권한이 자동으로 붙지 않아 직접 줌 (2026-11-17)
grant select, insert, update, delete on public.board_posts, public.board_comments, public.board_reports to service_role;
grant execute on function public.board_report_count(text, bigint, integer) to service_role;
