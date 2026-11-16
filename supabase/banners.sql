-- 안산살이 상단 배너 (2026-11-16): 지자체 행사·지역 광고를 홈 화면 맨 위에 보여줌.
-- schema.sql · admin.sql 다음에 SQL Editor 에서 실행. 다시 실행해도 안전합니다.
--
-- region 이 비어 있으면(null) 전국, '경기도 안산시'·'서울특별시'처럼 넣으면 그 지역 사용자에게만 보임 (공지와 같은 규칙).
-- lat·lng·radius_km 를 넣으면 당근처럼 '내 근처' 배너: 사용자 위치(위치 사용 켬 = GPS, 아니면 집 주소)에서 반경 안일 때만 보임.
-- 여러 개면 앱에서 가로로 넘기며 5초마다 자동으로 넘어감. sort 가 클수록 앞.

create table if not exists public.banners (
  id          uuid primary key default gen_random_uuid(),
  owner       text not null default '' check (char_length(owner) <= 80),   -- 관리용: 의뢰 기관·광고주 (앱에 안 보임)
  kind        text not null default 'event' check (kind in ('event', 'ad')),  -- event = 지자체·공공 행사, ad = 유료 광고 ('광고' 표시)
  region      text check (region is null or char_length(region) between 2 and 40),
  title       text not null check (char_length(title) between 1 and 40),   -- 한국어 제목
  sub         text not null default '' check (char_length(sub) <= 60),     -- 한국어 한 줄 설명
  title_en    text check (title_en is null or char_length(title_en) <= 60), -- 외국어 사용자에게 보일 영어 (비우면 한국어)
  sub_en      text check (sub_en is null or char_length(sub_en) <= 90),
  image_url   text check (image_url is null or image_url ~ '^https://'),   -- 3:1 이미지 (권장 1200×400). 있으면 글자 대신 이미지
  url         text check (url is null or url ~ '^https://'),
  -- 당근처럼 위치 기반 노출(선택): 중심 좌표 + 반경. 넣으면 그 반경 안에 있는 사용자에게만 보임 (지역 칸은 무시)
  lat         double precision check (lat is null or lat between 33 and 39),
  lng         double precision check (lng is null or lng between 124 and 132),
  radius_km   numeric(4,1) not null default 3 check (radius_km between 0.5 and 50),
  starts_at   date,                       -- 이 날부터 (비우면 바로)
  ends_at     date,                       -- 이 날까지 (비우면 계속)
  active      boolean not null default true,
  sort        integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists banners_region_idx on public.banners (region);
create index if not exists banners_geo_idx on public.banners (lat, lng) where lat is not null;
-- 이미 표를 만든 경우 (다시 실행 대비)
alter table public.banners add column if not exists lat double precision;
alter table public.banners add column if not exists lng double precision;
alter table public.banners add column if not exists radius_km numeric(4,1) not null default 3;

alter table public.banners enable row level security;
-- 앱(anon): 노출 중이고 기간 안인 것만 (날짜는 한국 시간 기준)
drop policy if exists "banners: read running" on public.banners;
create policy "banners: read running" on public.banners for select to anon, authenticated
  using (active
    and (starts_at is null or starts_at <= (now() at time zone 'Asia/Seoul')::date)
    and (ends_at   is null or ends_at   >= (now() at time zone 'Asia/Seoul')::date));
revoke all on public.banners from anon;
grant select (id, kind, region, title, sub, title_en, sub_en, image_url, url, lat, lng, radius_km, starts_at, ends_at, active, sort, created_at)
  on public.banners to anon;   -- owner 는 숨김

-- 관리자: 전체 관리
grant select, insert, update, delete on public.banners to authenticated;
drop policy if exists "banners: admin all" on public.banners;
create policy "banners: admin all" on public.banners for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop trigger if exists banners_touch on public.banners;
create trigger banners_touch before update on public.banners for each row execute function public.touch_updated_at();

-- 배너 이미지 저장소 (공개 읽기, 관리자만 올리기·지우기). 관리 페이지의 "이미지 올리기" 가 씀.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('banners', 'banners', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "banner images: admin write" on storage.objects;
create policy "banner images: admin write" on storage.objects for insert to authenticated
  with check (bucket_id = 'banners' and public.is_admin());
drop policy if exists "banner images: admin update" on storage.objects;
create policy "banner images: admin update" on storage.objects for update to authenticated
  using (bucket_id = 'banners' and public.is_admin()) with check (bucket_id = 'banners' and public.is_admin());
drop policy if exists "banner images: admin delete" on storage.objects;
create policy "banner images: admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'banners' and public.is_admin());
