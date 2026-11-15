-- 안산살이 전국 확장 (2026-11-15): 공지에 지역 추가. 다시 실행해도 안전합니다.
-- region 이 비어 있으면(null) 모든 지역에 보이는 전국 공지, '경기도 안산시'·'서울특별시'처럼 넣으면 그 지역 사용자에게만 보임.
alter table public.notices add column if not exists region text check (region is null or char_length(region) between 2 and 40);
create index if not exists notices_region_idx on public.notices (region);
-- 앱(anon)이 지역 열을 읽을 수 있게 (공개 공지 읽기 권한에 열 추가)
grant select (region) on public.notices to anon, authenticated;
-- 지금까지 올린 공지는 모두 안산 공지
update public.notices set region = '경기도 안산시' where region is null;
