# jobpost — 채용공고 작성·자동화 통합 도구

> 한 번 작성한 채용공고를 원티드·그리팅·리멤버 등 여러 플랫폼에 **반자동으로 등록**하는 도구. 두 컴포넌트로 구성.

## 두 컴포넌트

| 컴포넌트 | 역할 | 위치 |
|---|---|---|
| **jobpost 도구** | 채용공고 작성·관리·Supabase 동기화 (단일 HTML 파일, 8+ 플랫폼별 포맷 출력) | 이 레포 — `index.html`, `schema.sql` |
| **jobpost-bridge** | 작성된 공고를 원티드/그리팅/리멤버 페이지에 자동 입력 (3가지 배포 모드) | [`jd-extension` 레포](https://github.com/imchul-oss/jd-extension) — `extension`(루트), `userscript/`, `standalone/` |

```
┌──────────────────────────────────┐         ┌──────────────────────────────────┐
│  jobpost 도구 (index.html)       │ Supabase │  채용 플랫폼 (원티드/그리팅/리멤버)│
│  - 공고 작성·편집·다국어         │ ←─────→  │                                  │
│  - 플랫폼별 포맷 출력            │          │  ← jobpost-bridge가 폼 자동 입력  │
│  - 7테이블 정규화 동기화          │          │                                  │
└──────────────────────────────────┘         └──────────────────────────────────┘
```

## 빠른 시작 — 가장 쉬운 경로 (Chrome 확장)

### 1단계. Supabase 프로젝트 준비
- [supabase.com](https://supabase.com) 가입 → **New Project** 생성 (region 권장: `ap-northeast-1`)
- **SQL Editor** → `+ New query` → [`schema.sql`](./schema.sql) 전체 실행 (`Ctrl+Enter`) — 7개 테이블 + RLS + 인덱스 일괄 생성, 마지막에 검증 쿼리가 7개 row 반환
  - 로컬 클론이 없으면 GitHub raw URL에서 복사: <https://raw.githubusercontent.com/imchul-oss/jobpost/main/schema.sql>
  - CLI 일괄 적용: `curl -sSL https://raw.githubusercontent.com/imchul-oss/jobpost/main/schema.sql | psql "<connection-string>"`
- **Settings → API** 에서 `Project URL` 과 `anon public` key 복사
- 메타필드(`positions.metadata`)는 `schema.sql` v0.8.0+에 포함되어 별도 작업 불필요. 구버전 스키마로 설치했다면 `schema.sql` 재실행(idempotent) 또는 [`jd-extension`의 `schema-migrations/v0.11.0-metadata.sql`](https://github.com/imchul-oss/jd-extension/blob/main/schema-migrations/v0.11.0-metadata.sql) 실행

#### 자주 발생하는 에러
| 에러 | 원인 | 해결 |
|---|---|---|
| `Could not find the 'X' column ... in the schema cache` | PostgREST 캐시 stale | SQL 마지막의 `NOTIFY pgrst, 'reload schema';` 다시 실행 (또는 1-2분 대기) |
| `relation "positions" already exists` | 이전 실행 잔존 | `IF NOT EXISTS` 덕분에 무시됨 (정상) |
| `policy "Allow all" already exists` | 이전 실행 잔존 | `DROP POLICY IF EXISTS` 가 먼저 실행되므로 무시됨 (정상) |
| 앱 연결은 되는데 `Push 실패` | RLS 정책 누락 | SQL의 `CREATE POLICY` 7줄만 골라서 재실행 |

### 2단계. jobpost 도구로 공고 작성
- `index.html`을 브라우저로 열기 (file:// 직접 실행 가능)
- 우상단 `☁ Cloud` → Supabase URL + anon key 입력 → 연결
- `+ 추가` → 공고 작성 → 섹션별 콘텐츠 입력
- 자동 동기화 (3초 debounce)

### 3단계. Chrome 확장 설치
- `git clone https://github.com/imchul-oss/jd-extension.git` (별도 레포)
- `chrome://extensions/` → 개발자 모드 ON → "압축해제된 확장프로그램 로드"
- 클론한 `jd-extension/` 폴더 선택 → `jobpost-bridge` 등록 → 툴바 핀 고정

### 4단계. 사용
- 원티드/그리팅/리멤버 채용 작성 페이지 진입
- 툴바 아이콘 클릭 → 패널 창 열림
- ⚙️ 옵션 탭 → Supabase URL/key 입력 (jobpost와 동일 값)
- 📥 액션 탭 → 공고 선택 → "📥 가져와서 채우기"
- 페이지 폼이 자동 채워짐 → **저장은 사용자가 직접 클릭**

## jobpost 도구 — 본체

> 단일 HTML 파일, 외부 dependency 최소 (Supabase JS SDK + localforage CDN만).

### 핵심 기능
- **다중 플랫폼 출력**: 플랫폼별 불릿·줄바꿈·HTML 구조 한 번에 처리. 그리팅(Quill)·잡코리아(WYSIWYG)·원티드(separate 필드) 등 8+ 플랫폼
- **포지션 관리**: 직무별 KO/EN, Active/Closed, 보관·복원, ID 변경(Cascade Rename)
- **클라우드 동기화**: 7테이블 정규화, 3초 debounce, 충돌 방지
- **5중 데이터 안전망**: dirty 변경 우선 push · 로컬 스냅샷 · 손실 감지 · 자동 재push · 1시간 자동 백업
- **활동 로그**: 모든 동기화·rename·연결 이벤트 누적

### Supabase 스키마

| 테이블 | 역할 |
|---|---|
| `config` | 섹션·플랫폼·줄바꿈 설정 (JSONB, 단일 row) |
| `positions` | 직무 목록 + 상태 (`is_archived` 플래그) + 메타필드 (`metadata jsonb`, v0.8.0+) |
| `common_content` | 공통 콘텐츠 (KO/EN × 섹션) |
| `position_content` | 직무별 콘텐츠 (직무 × KO/EN × 섹션) |
| `posting_urls` | 직무별 플랫폼 게시 URL (자동 매칭용) |
| `recruit_snapshots` | 자동·수동 스냅샷 백업 (48개 한도) |
| `recruit_activity_log` | 활동 이력 |

상세 DDL: [`schema.sql`](./schema.sql). `recruit_` prefix는 다른 프로젝트와 Supabase 공유 시 충돌 방지용.

### 키 설계 결정
- **PK = `positions.name`** (text, 사람이 읽을 수 있는 ID). 표시명(`job_title`) 별도
- **ID 변경 cascade**: `🔑 ID 변경` 모달 → FK `ON UPDATE CASCADE`로 자식 자동 갱신
- **활성/보관 통합**: `is_archived` boolean으로 같은 테이블 관리

## jobpost-bridge — 자동화 모듈

원티드·그리팅·리멤버 등 외부 채용 페이지의 폼을 jobpost 데이터로 자동 채움.

### 3가지 배포 모드 (목적별 선택)

| 모드 | 위치 | 사용자 요건 | 적합한 상황 |
|---|---|---|---|
| **Chrome 확장** ⭐ 권장 | `extension/` v0.12.1 | 확장 설치 가능 환경 | 일반 사용 (옵션 UI·toast·a11y·다크모드 완비) |
| Tampermonkey 유저스크립트 | `userscript/` v0.9.3 | Tampermonkey 또는 ScriptCat | 확장 대신 매니저 선호 시 |
| Standalone (Playwright) | `standalone/` | Node.js 18+ | 확장 제한 환경 |

세 모드 모두 **같은 핵심 로직**(셀렉터·어댑터·자동 매칭) 사용. 상세 사용법은 [USER_GUIDE.md](https://github.com/imchul-oss/jd-extension/blob/main/docs/USER_GUIDE.md) (jd-extension 레포).

### 지원 플랫폼

| 플랫폼 | 페이지 | 상태 |
|---|---|---|
| 원티드 | `wanted.co.kr/dashboard/recruitment/*` (신규/수정) | ✓ 검증 완료 |
| 그리팅 popup | `app.greetinghr.com/.../integration-platform/wanted/required` | ✓ |
| 그리팅 본 공고 | `app.greetinghr.com/.../{edit_opening,new_opening}/*` (Quill 1.3.6) | ✓ |
| 리멤버 | `hr.rememberapp.co.kr/*` · `career.rememberapp.co.kr/*` | ✓ |
| 사람인·잡코리아·인디드(+글래스도어) | (placeholder, selector 수집 필요) | 미완성 |

### 자동 매칭 시스템

페이지 진입 시 3-tier resolver가 jobpost 공고를 자동 식별:

| 신뢰도 | 의미 | 활용 |
|---|---|---|
| 🎯 정확 매칭 | `posting_urls` 테이블에 등록된 URL과 일치 | 즉시 fill 가능 |
| 🔍 유사 매칭 | 페이지 제목 퍼지 매칭 발견 | 정확도 보통 |
| 🤔 추정 매칭 (등록 필요) | 매칭 의심 | "✓ 매칭하고 등록" 한 번 누르면 다음부터 🎯 |

자기-부트스트랩: 사용자가 자연스럽게 사용만 해도 `posting_urls`가 누적됨.

## 보안 메모

- **anon key는 코드 미포함**. 사용자가 직접 입력 → 격리 저장:
  - jobpost 도구: `localStorage` (file:// origin)
  - Chrome 확장: `chrome.storage.local`
  - Tampermonkey: `GM_setValue`
- **legacy anon JWT(`eyJ...`) 사용 권장** — 새 `sb_publishable_*` 포맷은 기존 RLS와 비호환 사례 있음 ([상세 — jd-extension README](https://github.com/imchul-oss/jd-extension/blob/main/README.md))
- RLS 정책은 schema.sql 기본 `Allow all` (단독·소수 사용 가정). 다중 사용자 시 인증 정책 교체 필요
- 직무 데이터(`*_data.json`) commit 안 함 (`.gitignore`)

## ToS 안내 (필독)

- 원티드·리멤버 약관은 자동화 도구 제한 조항이 있음 (Remember 기업 ToS 제10조의2 §1 6호 "매크로 프로그램" 명시 금지)
- 본 도구는 **form 필드 자동 입력만** 수행. **저장·제출은 사용자가 직접 클릭** — 위험 감소이지 약관 준수가 아님
- 원티드 수정 시 24시간 재승인 절차 발동
- 모든 동작은 `recruit_activity_log`에 기록
- **사용은 사용자가 정보에 기반하여 감수하는 위험**

## 디렉토리 구조

두 레포로 분리 발행됩니다.

```
jobpost/  (이 레포)
├── index.html                         jobpost 도구 본체 (단일 HTML 파일)
├── schema.sql                         Supabase 테이블 DDL
├── CHANGELOG.md                       jobpost 도구 변경 이력
└── README.md                          이 문서

jd-extension/  (https://github.com/imchul-oss/jd-extension)
├── manifest.json                      Chrome 확장 MV3 (권장 배포 모드, 레포 루트째 로드)
├── background/service-worker.js       탭 상태 추적 + 메시지 라우팅
├── content/content-script.js          어댑터·셀렉터·fill 로직
├── panel/                             별도 popup 창 UI (액션·옵션·진단 3탭)
├── icons/                             16/48/128 PNG
├── schema-migrations/                 v0.11.0-metadata.sql 등
├── userscript/                        Tampermonkey·ScriptCat 유저스크립트 (v0.9.3 동결)
├── standalone/                        Playwright 자체 실행 (확장 제한 환경용)
└── docs/                              USER_GUIDE.md + verified 셀렉터 자료
```

## 변경 이력 요약 (jobpost-bridge)

- **v0.1.0~0.3.0** (userscript): 스켈레톤·클립보드 채널·그리팅 popup 어댑터
- **v0.4.0~0.7.0** (userscript): Supabase 직접 fetch·자동 매칭·URL 등록·title 매칭 제안
- **v0.8.0~0.9.3** (userscript): 원티드·리멤버·그리팅 본 공고 어댑터 + 포맷 옵션 외부화. **userscript 동결**
- **v0.10.0** (extension): Chrome MV3 확장 신규. 별도 popup window UI, 3탭, 옵션 GUI
- **v0.11.0~0.11.4**: P2 combobox · 새 플랫폼 placeholder · 메타필드 모델 · QA 패치 · UI/UX 통합
- **v0.11.5~0.11.8**: URL 감지 광범위화 · 그리팅 신규 페이지 · 리멤버 명시 URL 패턴 · 자동 강제 주입 fallback
- **v0.12.0** (이번 사이클): 메타필드 GUI(jobpost 도구) · SPA 라우팅 자동 재감지(pushState/replaceState/popstate/hashchange wrap + 150ms debounce) · 그리팅 Quill MAIN world 동적 주입(Delta sync 보장) · 다크 모드 + CSS 변수 50+ 토큰화
- **v0.12.1** (현재): UX 5종 추가 — 버전 동기화(DEV-003) · 채우기 toast 요약(DEV-004) · positionsCache 5분 TTL(DEV-005) · Ctrl/Cmd+Enter 단축키(DEV-006) · 패널 창 크기 메모리(DEV-010)

## 완료된 작업 (v0.12.x 사이클)

- jobpost UI 메타필드 입력 폼 — `index.html`에 `<details>` 카드, 7+1 키 GUI 편집(직군·고용형태·경력·연봉·마감일·근무지·기타옵션 + _opened 상태)
- `_sbPush`/`_sbPull`에 `positions.metadata` 컬럼 동기화 + 마이그레이션 미실행 시 graceful fallback
- SPA 라우팅 자동 재감지 — 그리팅 사이드바 클릭 시 F5 없이 패널 ctx 자동 갱신
- 그리팅 본 공고 Quill 안정성 — `chrome.scripting.executeScript({world:'MAIN'})`로 `Quill.find`·`clipboard.dangerouslyPasteHTML` 직접 호출, Delta 정렬 보장. MAIN 실패 시 execCommand → innerHTML fallback 2단계
- 다크 모드 — `:root` semantic 토큰 + `[data-theme]` 수동 override + `prefers-color-scheme` auto + 옵션 카드(자동/라이트/다크). FOUC 방지용 head inline script
- 추가 UX 5종 — VERSION 단일 상수 → 헤더·진단 동기화, 채우기 toast 요약, 공고 목록 5분 TTL, Ctrl/Cmd+Enter 단축키, 패널 창 크기·위치 자동 기억

## 미완성 백로그 (사용자 액션 필요)

- 사람인·잡코리아·인디드(+글래스도어) verified selector 수집 + 어댑터 통합 — DOM 캡처 필요
- 잡코리아 iframe WYSIWYG 처리 — selector 수집 후 가능
- 그리팅 본 공고 Quill Delta sync 검증 — 저장 후 reload 시 본문 유지 사용자 확인 필요
- 원티드 직군/직무 combobox selector 수집
- Chrome Web Store 공개 배포 — 유료 계정·심사 필요

## 기여 원칙

- jobpost 도구: 단일 HTML 파일 구조 유지, 외부 dependency 최소
- jobpost-bridge: 어댑터별 셀렉터·매핑은 `extension/content/content-script.js`에 집중. 새 플랫폼 추가 시 SEL · PLATFORM_FIELD_MAP · ADAPTERS 3곳만 수정
- 한국어 UI 우선. 코드 주석 한·영 혼용 가능
- Supabase 스키마 변경 시 `schema.sql` (jobpost 본체) 또는 `extension/schema-migrations/` 동시 업데이트

## 라이선스

[MIT](./LICENSE)

## 작성자

[@imchul-oss](https://github.com/imchul-oss)
