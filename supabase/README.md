# Supabase 설정 · 운영

안산살이는 Supabase를 **공지·광고 관리**와 **설문 응답 저장**에 씁니다. 별도 관리자 화면 대신 Supabase 대시보드의 **Table Editor**가 관리 화면입니다.

## 1. 처음 설정 (10분)

1. [supabase.com](https://supabase.com) 가입 → **New project**
   - Region: **Northeast Asia (Seoul)** 를 고르세요 (개인정보 국외 이전을 줄이기 위해).
   - Database password 는 안전한 곳에 보관.
2. 왼쪽 **SQL Editor** → `supabase/schema.sql` 내용을 통째로 붙여 넣고 **Run**. 다시 실행해도 안전합니다.
3. **Project Settings › API** 에서 두 값을 복사합니다.
   - Project URL (`https://xxxx.supabase.co`)
   - **anon / publishable** 키 (공개용). `service_role` / secret 키는 **절대** 앱이나 이 저장소에 넣지 마세요.
4. 앱 빌드에 넣습니다.
   ```bash
   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_ANON_KEY=<anon 키> \
   NAVER_KEY=... API_URL=... python3 build.py
   ```
5. 공지 번역은 아래 3장의 API(Edge Function)가 Supabase 공지를 바로 읽습니다. 따로 설정할 것 없음.

## 3. API 서버 (Edge Function `api`) — 현재 운영 방식

사진 분석·버스·병원/약국·공지 번역 API 를 Cloudflare 대신 **Supabase Edge Function** 으로 돌립니다. 코드 원본은 `server/worker.js` 하나이고, `supabase/build_edge.py` 가 이를 Edge Function 용 `supabase/functions/api/index.ts` 로 바꿉니다.

- 주소: `https://<ref>.supabase.co/functions/v1/api` (현재 `https://mriuywhiaaslmcdrfhfh.supabase.co/functions/v1/api`)
- 캐시·횟수 제한: Cloudflare KV / Rate Limiting 대신 `supabase/edge.sql` 의 `kv_cache`, `rate_hits`, `rate_hit()` (IP당 60초에 20회)
- **Verify JWT 는 켠 채로 둡니다.** 앱이 공개 anon 키(JWT, `role=anon`)를 `authorization`·`apikey` 헤더로 보냅니다. 빌드 변수 `API_KEY` — `build.py` 가 role 이 anon 이 아니면 빌드를 멈춥니다.

**배포 순서**
1. SQL Editor 에서 `supabase/edge.sql` 실행 (한 번)
2. `python3 supabase/build_edge.py` → `supabase/functions/api/index.ts` 생성
3. 대시보드 **Edge Functions › api › Code** 에 붙여 넣고 **Deploy updates** (또는 `supabase functions deploy api`)
4. **Edge Functions › Secrets** 에 키 입력
   | 이름 | 값 | 없으면 |
   | --- | --- | --- |
   | `ANTHROPIC_API_KEY` | Claude API 키 (console.anthropic.com) | 사진 분석·공지 번역 안 됨 (`config` 오류) |
   | `DATA_GO_KR_KEY` | 공공데이터포털 **Decoding** 인증키 | 버스·병원·약국 예시 데이터 |
   | `BUS_KEY` (선택) | 버스 API 를 다른 계정으로 신청했을 때만 | `DATA_GO_KR_KEY` 사용 |
   | `ALLOWED_ORIGIN` (선택) | 앱 주소, 쉼표로 여러 개 | 기본: gogeangs·eugenekimkim github.io |
   `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` 는 Supabase 가 자동으로 넣어 줍니다.
5. 앱 빌드
   ```bash
   API_URL=https://<ref>.supabase.co/functions/v1/api API_KEY=<anon JWT (Legacy API keys 탭)> \
   SUPABASE_URL=... SUPABASE_ANON_KEY=... NAVER_KEY=... python3 build.py
   ```

**무료 플랜 주의:** 7일 동안 요청이 없으면 프로젝트가 일시 정지됩니다(대시보드에서 Resume). 정식 출시 때는 Pro($25/월) 권장.

## 2. 공지 관리 페이지 (admin.html) — 추천

앱과 같은 주소의 `admin.html` 에서 공지를 쓰고, 고치고, 게시를 켜고 끄고, 순서를 바꿀 수 있습니다. 오른쪽에 앱에서 보일 모습이 바로 나옵니다.
시험 주소: https://gogeangs.github.io/ansanlife-dev/admin.html

**처음 한 번: 관리자 계정 만들기**

1. SQL Editor 에서 `supabase/admin.sql` 실행 (관리자 권한 규칙)
2. **Authentication › Users › Add user › Create new user** — 이메일·비밀번호 입력, **Auto Confirm User** 체크
3. SQL Editor 에서 그 사람을 관리자로 등록
   ```sql
   insert into public.admins (user_id, note)
   select id, '대표' from auth.users where email = '관리자 이메일'
   on conflict do nothing;
   ```
4. **Authentication › Sign In / Providers** 에서 **Allow new users to sign up** 을 끄기 (아무나 가입하지 못하게)

관리자를 빼려면 `delete from public.admins where user_id = (select id from auth.users where email = '…');`

## 3. 표에서 직접 관리 (Table Editor)

| 하고 싶은 일 | 표 | 방법 |
| --- | --- | --- |
| 공지·행사 올리기 | `notices` | Insert row → `title`, `body` 를 **한국어로** 입력, `type` 은 official(공지) / event(행사), `published` 를 true 로. 번역은 자동 |
| 공지 내리기 | `notices` | `published` 를 false 로 |
| 위로 올리기 | `notices` | `sort` 숫자를 크게 |
| 예시 공지 지우기 | `notices` | `sample` 이 true 인 행 삭제 |
| 광고 등록 | `ads` | `advertiser`(관리용), `langs`(보여줄 언어, 예: `{vi}` 베트남어만, `{ru,uz}`), `title`(최대 80자, 그 언어로), `body`(최대 160자), `url`(https), `image_url`(https, 정사각형), `starts_at`/`ends_at`(기간) |
| 광고 잠시 끄기 | `ads` | `active` 를 false 로 |
| 광고 노출 비율 | `ads` | 같은 언어에 여러 개면 `weight` 비율로 무작위 노출 |
| 설문 결과 보기 | `survey_responses` | 표에서 보거나 **Export to CSV**. `answers` 는 문항별 선택 코드(예: `["van","bus","week"]`) |

언어 코드: `en` 영어 · `vi` 베트남어 · `ko` 한국어 · `zh` 중국어 · `ru` 러시아어 · `uz` 우즈베크어 · `mn` 몽골어

## 4. 보안 규칙 (schema.sql · admin.sql)

앱이 쓰는 공개 키로 할 수 있는 일은 세 가지뿐입니다. 로컬 Postgres 16 에서 확인했습니다.

- 게시된(`published`) 공지 읽기
- 지금 노출 중인(`active`, 기간 안) 광고 읽기 — `advertiser` 열은 못 읽음
- 설문 응답 **쓰기** — 읽기·수정·삭제는 못 함, 언어 코드·크기 검사

등록·수정·조회는 대시보드 관리자, 또는 `admins` 표에 등록된 계정으로 관리 페이지에 로그인한 사람만 할 수 있습니다. 로그인만 하고 `admins` 에 없으면 아무것도 바꾸지 못합니다(로컬 Postgres 16 에서 확인).

## 5. 광고 네트워크 (선택)

직접 계약 광고가 없는 언어에는 애드센스가 대신 나옵니다. 애드센스 승인 후 빌드에 넣으세요.

```bash
ADSENSE_CLIENT=ca-pub-xxxxxxxxxxxx ADSENSE_SLOT=xxxxxxxxxx python3 build.py
```

광고 제거(설문 보상) 중에는 직접 광고·애드센스 모두 숨깁니다. 애드센스는 쿠키를 쓰므로 개인정보 처리방침에 적어야 합니다(`docs/PRIVACY_DRAFT.md`).
