# 안산살이 (Ansan Life)

안산 거주 외국인 주민을 위한 다국어 생활 안내 모바일웹 프로토타입입니다.
분리배출, 버스·교통, 관공서, 병원, 공지·행사, 일자리, 설문을 한곳에서 안내합니다.

- 운영 언어: 한국어 · English · Tiếng Việt · 中文 · Русский · O‘zbekcha · Монгол (베트남어 이후 5개 언어는 AI 번역 · 원어민 검수 전)
- 디자인 시안: Figma "아이디어_안산시생활지원" (Page 1)
- 인수인계 메모: [docs/HANDOFF.md](docs/HANDOFF.md)

## 빠르게 실행하기

```bash
python3 build.py          # index.html 생성
python3 -m http.server    # http://localhost:8000 에서 확인
```

빌드에 넣는 값(지도 키, API 주소, Supabase 공개 키, 일자리 key 등)은 저장소 맨 위의 `build.env` 에 `이름=값` 줄로 적어 두면 `build.py` 가 매번 읽습니다. 이 파일은 커밋되지 않습니다(`.gitignore`). 같은 이름을 명령에서 직접 주면 그 값이 먼저입니다.

빌드 없이 보려면 저장소에 들어 있는 `index.html` 을 그대로 열어도 됩니다.

## 네이버 지도 켜기

1. 네이버 클라우드 콘솔 › Maps › Application 등록
   - **Dynamic Map**, **Geocoding**, **Reverse Geocoding** 체크 (Reverse Geocoding 은 GPS 로 동네를 바꿀 때 씀)
2. Web 서비스 URL 에 배포할 도메인 등록 (포트·경로 없이 호스트만)
3. 발급받은 Client ID 로 빌드

```bash
NAVER_KEY=발급받은_Client_ID python3 build.py
```

키가 없거나 인증에 실패하면 그림 지도가 대신 보여서 화면이 깨지지 않습니다.
지역 "변경"도 키 없이 동작하지만, 이때는 GPS 위치를 주소로 바꾸지 못해 주소를 직접 입력하게 안내합니다.

## API 서버 켜기 (사진 분석 · 버스 실시간 · 공지 번역)

`server/worker.js` 하나가 API 를 모두 맡고, **Supabase Edge Function** 으로 돌립니다(Cloudflare Worker 로도 배포 가능). 배포 방법은 [supabase/README.md](supabase/README.md) 3장, 경로 설명은 [server/README.md](server/README.md) 에 있습니다.

| 기능 | 필요한 키 (Worker secret) | 서버 없을 때 |
| --- | --- | --- |
| 사진으로 물어보기 | `ANTHROPIC_API_KEY` | 카메라는 동작, 결과는 "예시 결과" |
| 주변 정류장 · 도착 시간 | `DATA_GO_KR_KEY` | Sample 정류장·도착 시간 |
| 공지 번역 (`data/notices.json`) | `ANTHROPIC_API_KEY` + `NOTICES_URL` | 화면에 넣어 둔 예시 공지 |

```bash
NAVER_KEY=발급받은_Client_ID API_URL=https://ansanlife-api.계정.workers.dev python3 build.py
```

공지는 `data/notices.json` 에 **한국어 원문**으로 넣으면, 서버가 사용자의 언어로 번역하고(내용이 바뀔 때만) 앱에서 "원문 보기"로 한국어를 볼 수 있습니다.

## 일자리 (오퍼센트 채용공고)

홈의 '일자리' 메뉴는 오퍼센트에 게시 중인 채용공고를 보여주고, 지원은 공고마다 오는 `applyUrl`(오퍼센트 공고 화면)로 보냅니다. 서버 없이 화면 스크립트가 `https://api.opercent.ai/api/ext/v1/jobs/…` 를 **브라우저 key**(허용 도메인으로 묶인, 화면 소스에 보여도 되는 key)로 바로 부릅니다.

| `build.env` 이름 | 값 | 쓰는 곳 |
| --- | --- | --- |
| `OPERCENT_KEY` | 운영 key `opc_live_…` (허용 도메인 sari.kr) | localhost 가 아닌 모든 주소 |
| `OPERCENT_TEST_KEY` | 테스트 key `opc_test_…` (허용 도메인 localhost:8000) | `http://localhost:8000` 에서만. 포트가 다르면 CORS 오류 |

커밋하는 `index.html` 에는 테스트 key 를 넣지 않습니다: `OPERCENT_TEST_KEY= python3 build.py` 로 빌드해 커밋하고, 내 컴퓨터에서 시험할 때만 그냥 `python3 build.py`.

그 주소에 맞는 key 가 없으면 일자리 메뉴가 숨겨집니다. 오퍼센트와 약속한 규칙(오퍼센트 「채용공고 API 가이드」 §3-1·§7):

- 분당 호출 한도를 방문자 모두가 함께 씀 → 언어별 전체 목록을 한 번에 받아(50건씩, 최대 500건) 기기(localStorage)에 10분 보관하고(다른 탭·다시 열어도 그 안이면 안 부름. 중간 페이지가 잠깐 실패하면 받은 데까지 보여 주고 '다시 시도'), 지역 탭·고용형태·한국어·체류자격 거르기는 기기 안에서 함(거르기를 눌러도 다시 부르지 않음). 429 면 `Retry-After` 동안 부르지 않음
- '내 지역' 탭은 공고의 시군구 코드 또는 근무지 주소(`경기도 안산시 …`)로 판단
- 공고 곁에 '오퍼센트' 표시, 지원은 `applyUrl` 그대로(안산살이는 지원서를 받지 않음)
- 공고 내용은 받은 그대로. 공지 번역 기능 등 기계번역 금지. 우즈베크어·몽골어 화면은 `lang=en` 으로 받음
- `description` 은 글자로(이스케이프 + 줄바꿈만), 마감 지남·한 건 조회 404 는 바로 내림, 503·잠깐의 CORS 오류(오퍼센트 배포 중)에는 내리지 않음
- 시험 중에 오퍼센트 화면의 지원 버튼은 누르지 말 것(사업주에게 실제 지원이 감)

## 공지 관리 페이지

`admin.html` 에서 로그인한 관리자가 공지를 쓰고, 고치고, 게시를 켜고 끄고, 순서를 바꿉니다. 앱에서 보일 모습이 바로 옆에 미리 나옵니다. 관리자 계정 만드는 법은 [supabase/README.md](supabase/README.md) 2번.

## Supabase 켜기 (공지·광고 관리, 설문 저장)

공지·광고 등록과 설문 결과 확인은 Supabase 대시보드에서 합니다. 처음 설정과 운영 방법은 [supabase/README.md](supabase/README.md) 에 있습니다.

```bash
SUPABASE_URL=https://xxxx.supabase.co SUPABASE_ANON_KEY=<anon 키> python3 build.py
# 직접 광고가 없을 때 애드센스: ADSENSE_CLIENT=ca-pub-... ADSENSE_SLOT=...
```

Supabase 없이 빌드하면 예시 광고가 나오고, 설문 응답은 기기에만 남습니다.

## 버스 경로

목적지(자주 가는 곳 또는 주소 검색)를 고르면 **네이버지도 대중교통 길찾기**가 집 주소에서 출발하도록 열립니다(`nmap://route/public`). 네이버 키가 없거나 장소 이름이라 좌표를 못 찾으면 네이버지도 장소 검색으로 엽니다.

## 앱으로 설치 (PWA)

`manifest.webmanifest` 와 `sw.js` 가 함께 배포되면 휴대폰에서 "홈 화면에 추가"로 앱처럼 설치되고, 한 번 열었던 화면은 오프라인에서도 열립니다. 안드로이드는 홈에 설치 카드가 뜨고, 아이폰은 "공유 → 홈 화면에 추가" 안내가 뜹니다. `--inline` 단일 파일(아티팩트용)에서는 꺼집니다.

## 구글 지도 (네이버 지도 키가 없을 때)

병원·약국 목록 지도, 병원 상세 지도, 정류장·관공서 지도는 네이버 지도 키가 있으면 네이버, 없거나 인증에 실패하면 구글 지도로 그립니다.

1. Google Cloud 콘솔 › API 및 서비스 › 사용 설정: **Maps JavaScript API** (집 주소 → 좌표 변환까지 쓰려면 **Geocoding API** 도)
2. 사용자 인증 정보 › 해당 키 › **애플리케이션 제한: 웹사이트** 에 `https://gogeangs.github.io/*` 와 실제 도메인, **API 제한** 은 위 두 API 만
3. `GMAPS_KEY=AIza... python3 build.py`

브라우저용 지도 키는 페이지 소스에 그대로 보이므로 반드시 2번의 웹사이트 제한을 걸어 두세요. 키는 저장소에 커밋하지 말고 빌드할 때만 넣습니다.

## 배포 (예: GitHub Pages)

저장소 Settings › Pages › Branch `main` / root 로 설정하면 `index.html` 이 바로 열립니다.
카메라 실시간 화면과 GPS 는 **HTTPS** 에서만 동작하므로 Pages 같은 HTTPS 호스팅에서 시험하세요.

## 폴더 구조

| 경로 | 내용 |
| --- | --- |
| `src/app.template.html` | 앱 원본 (CSS + JS 한 파일). 수정은 여기서 |
| `build.py` | 템플릿 → `index.html` 빌드, `--inline` 은 이미지 내장 단일 파일 |
| `build.env` | 빌드 값(키·주소). 커밋 안 됨, 각자 만들어 씀 |
| `index.html` | 빌드 결과. 지금은 Supabase(서울, 공개 키)만 연결해 빌드됨. 네이버 키·API 서버는 아직 |
| `manifest.webmanifest`, `sw.js` | 앱 설치(PWA) · 오프라인 |
| `data/notices.json` | Supabase 를 쓰기 전 임시 공지 원문 (서버가 번역) |
| `assets/` | 인트로 배경 이미지 (주황 노을, 하늘색), 원본 PNG, 앱 아이콘 |
| `server/` | API 서버 원본 (`worker.js`): 사진 분석, 경기도 버스, 병원·약국, 공지 번역. `supabase/build_edge.py` 로 Edge Function 변환 |
| `supabase/` | DB 스키마·보안 규칙(`schema.sql`), 관리자 권한(`admin.sql`), 설정·운영 방법 |
| `src/admin.template.html` → `admin.html` | 공지 관리 페이지 (빌드 시 Supabase 공개 키가 들어감) |
| `docs/HANDOFF.md` | 인수인계 메모: 디자인 규칙, 구현 상태, 남은 일, 출처 |
| `docs/CHECKLIST.md` | 출시 전 확인·신청 목록 (안산시 문의, API 신청, 번역 검수) |
| `docs/PRIVACY_DRAFT.md` | 개인정보 처리·동의 문구 초안 (법률 검토용) |

## 코드 구조 한눈에

- 화면은 `SCR.<이름>()` 함수가 HTML 문자열을 돌려주는 방식 (`intro`, `home`, `w1`–`w6` 분리배출, `b1`–`b6` 교통, `hosp`, `hdetail`, `offices`, `news`, `surv`, `sq`, `sdone`)
- 상태는 `st` 객체, 화면 이동은 `go()` / `back()` / `home()`
- 문구는 `S.en` / `S.vi` / `S.ko` / `S.zh` / `S.ru` / `S.uz` / `S.mn` 사전 (키 226개, 모두 같은 구조)
- 네이버 지도 연동: `NAVER_KEY`, `MAPS`, `mountMaps()`
- 네이버지도 앱/웹 열기: `openNaver()`, `nApp()`, `nWeb()`
- 집 주소: `st.addr`, 지역 변경 시트 `locSheet()`, 좌표→주소 `revGeo()`
- 카메라: `startCam()` / `capture()` / `stopCam()`, 사진 분석: `API_URL`, `analyze()`, `runScan()`, 결과 분류 `DEST`
- 단지별 배출 요일: `st.rules`, `CITY`(안산시 기본값), `sched()`, 편집 화면 `SCR.rules`
- 버스 실시간: `loadStops()`, `loadArr()` (30초마다 갱신) · 경로: `PLACES`, `routeTo()` → 네이버지도 · 공지: `loadNews()`, `SCR.ndetail`
- 일자리: `opc()`(오퍼센트 호출 + 10분 보관 `JC`), `jLoad()`·`jFetchList()`(전체 목록, 한 덩어리로 보관), `jList()`/`jMatch()`(기기 안 거르기), 내 지역 `jNearFn()`(시군구 코드 `jRegionMatch()` 또는 근무지 주소), `SCR.jobs`, `SCR.jdetail`, 문구 `JT_`
- Supabase: `sb()`, 광고 `adSlot()`/`loadAd()`(직접 → 애드센스), 설문 `saveSurvey()`(실패 시 기기에 모았다 재전송)
- 언어: `COUNTRIES`, `S.<언어>`, `DAYS`, `DAYLONG`, `LOCALE` (키릴·중국어는 `.l-ru/.l-mn/.l-zh` 글꼴)

## 수정 후

`src/app.template.html` 을 고친 뒤 `python3 build.py` 로 `index.html` 을 다시 만들어 함께 커밋하세요.
