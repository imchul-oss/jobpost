# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다.
포맷: [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/), [Semantic Versioning](https://semver.org/lang/ko/).

## [0.8.0] — 2026-06-11 (메타데이터 카드 + 동기화 정합성 패치)

### Added
- **메타데이터 카드**: 포지션별 `<details>` 카드에서 직군·고용형태·경력·연봉·마감일·근무지·기타옵션 GUI 편집 (`renderMetadataCard`/`setMeta`)
- `_sbPush`/`_sbPull`에 `positions.metadata jsonb` 동기화 + 컬럼 미존재 시 graceful fallback (이번 패치부터 toast로도 안내)
- `schema.sql`에 `positions.metadata jsonb DEFAULT '{}'` 포함 + 기존 설치용 `ADD COLUMN IF NOT EXISTS` (idempotent) — 이 레포만으로 신규 셋업 시 메타필드 동기화 누락되던 문제 해소

### Fixed
- **posting_urls push가 jd-extension 자동 매칭 데이터를 파괴 (Critical)**:
  - 기존 push가 모든 체크 페어를 `url='Y'`로 upsert → 확장이 등록한 실제 페이지 URL이 `'Y'`로 덮어씌워져 🎯 정확 매칭 불능
  - 기존 stale 삭제가 로컬 미체크 페어를 전부 삭제 → 확장이 등록한 URL row까지 삭제
  - 수정: 클라우드에 없는 페어만 insert (기존 row의 url 보존), 삭제는 jobpost가 만든 `url='Y'` 마커에만 한정
- **비운 섹션 텍스트가 pull 때 부활**: `position_content` stale 정리가 포지션 단위뿐이어서, 내용을 비우거나 섹션을 삭제해도 클라우드 row가 남아 다음 pull에서 복원됨 → `common_content`와 동일한 (position_name, lang, section_key) 페어 단위 정리로 수정
- **miniMd 링크 XSS**: `[텍스트](javascript:...)`가 클릭 실행 가능한 `<a href>`로 변환되던 것을 http(s) 스킴만 허용하도록 수정 (그 외는 원문 그대로 출력)

### Removed
- `📤 매크로로 전송` 버튼 + `buildBridgePayload`/`sendToBridge` — 클립보드 payload 채널은 userscript v0.1.0~0.3.0 시절 설계로, 현행 확장·userscript 모두 Supabase 직접 fetch라 읽는 쪽이 없는 죽은 기능

### Docs
- README 테이블 수 표기 통일 (6테이블 → 7테이블), 타 레포로 이동한 `docs/USER_GUIDE.md`·`extension/README.md` 링크를 jd-extension GitHub 경로로 교정, 낡은 라인 수 표기 제거
- schema.sql 헤더 버전 v0.8.0으로 갱신

## [0.7.1] — 2026-06-01 (셋업 SQL 개선)

### Changed
- `schema.sql` 재실행 안전성 강화:
  - 모든 `CREATE POLICY` 앞에 `DROP POLICY IF EXISTS` 선행
  - 끝부분에 7개 테이블 검증 쿼리 자동 실행
  - `NOTIFY pgrst, 'reload schema';` 명시 추가 (PostgREST 캐시 즉시 갱신)
- `README.md` 셋업 가이드 강화: GitHub raw URL 안내, `psql` 일괄 적용 옵션, 자주 발생하는 에러 표

## [0.7.0] — 2026-04-28 (Sprint 1: 활동 로그 인프라)

### Added
- **F10: 활동 로그 시스템** (`recruit_activity_log` 테이블)
  - `logActivity(type, level, msg, context)` 코어 함수
  - push / pull / rename / connect / disconnect 5종 hook
  - 오프라인 시 100건 버퍼링 → 재연결 시 자동 flush
  - 5% 확률 자동 정리 (500건 한도)
  - 클라우드 모달에 `📝 활동 로그` 섹션 + [새로고침]으로 최근 20건 조회
  - `client_id` 로 다탭/다기기 추적

### Infrastructure
- R1 가드 (매 Edit 후 끝부분/문법 자동 검증) 워크플로우 정책화

## [0.6.0] — 2026-04-28 (ID 변경 모달 UX 강화)

### Fixed
- ID 변경 모달 [닫기] 버튼 무반응 — `document.body.insertAdjacentHTML` → `$('modalRoot').innerHTML = h` 로 통일 (다른 모달과 동일 패턴)

### Added
- 4중 닫기 안전망 (`tryCloseRename`):
  - 헤더 [닫기] / 하단 [취소] / 모달 배경 클릭 / Esc 키 — 입력 변경 있으면 저장 여부 confirm
  - `Enter` 단축키 — 즉시 저장 후 닫기 (`commitRename`)
- 입력 필드 자동 포커스 + 전체 선택
- 라벨에 단축키 안내, 버튼 라벨 명확화 (`[변경]` → `[💾 저장 후 닫기]`)

## [0.5.0] — 2026-04-28 (데이터 손실 방지 5중 안전망)

### Fixed
- **재연결 시 데이터 손실 버그** (Critical)
  - 원인: `_sbInit()` 이 무조건 `_sbPull()` 호출 → dirty 로컬 변경분이 클라우드 옛 데이터로 덮어씌워짐
  - F1: `_sbInit(autoSync)` 시그니처 — `'pull'` / `'push'` / `'auto'` 분기
  - F2: `sbConnect()` → `_sbInit('auto')` (dirty면 push 우선 → pull)
  - F3: `_sbPull()` 진입 직전 `localStorage['jobpost_safety_before_pull']` 백업
  - F4: `checkSafetyDiff()` — pull 후 데이터 100자+ 손실 감지 시 confirm + 1클릭 복구 + 자동 push
  - F5: `window.addEventListener('online')` — 네트워크 복귀 시 dirty 자동 push

### Database
- `config.archived jsonb DEFAULT '[]'` 컬럼 추가 (보관 목록 클라우드 동기화)
- `recruit_snapshots` 테이블 신설 (자동 백업, 1시간 간격 + 이벤트 기반, 최대 48개)

## [0.4.0] — 2026-04-28 (Sprint 0: Cascade Rename + Supabase 정합성)

### Fixed
- **공고 ID-라벨 불일치 (Critical)**: `D.jobTitles` 변경이 `D.positions` 키(=Supabase PK)와 분리되어 키 변경 불가
  - `renamePositionKey(oldName, newName)` cascade rename 함수 추가
  - 로컬: `D.positions`, `D.data`, `D.jobTitles`, `D.posLang`, `D.posStatus`, `D.postedPlatforms`, `D.archivedOrigOrder`, `D.archived` 동시 키 마이그레이션
  - Supabase: `positions.name` UPDATE 한 번으로 자식 테이블 자동 갱신 (FK CASCADE)
  - UI: 공고명 입력 아래 `ID:` 표시 + `🔑 ID 변경` 모달
- **duplicatePosition `(복사)` 중복**: jobTitle suffix 추가 로직 제거 (newName 키에 이미 들어있음)
- **posting_urls 복합키 stale 정리**: `id` 컬럼 가정 제거 → `(position_name, platform_id)` 페어별 `Promise.all` 병렬 delete

### Database
- `position_content`, `posting_urls` FK에 `ON UPDATE CASCADE` 추가 (이전: NO ACTION)
- `positions.is_archived boolean` 컬럼 추가 (보관 포지션도 같은 테이블에서 관리, content FK 보존)

## [0.3.0] — 2026-04-26 (스냅샷 + 보관 시스템)

### Added
- `recruit_snapshots` 자동/수동 백업
  - 1시간 간격 + 보관/삭제 직전 자동
  - 최대 48개 보관, 초과 시 오래된 것부터 정리
  - 클라우드 모달에 스냅샷 목록 + 복원 버튼

### Fixed
- 보관 → 복원 시 원래 정렬 순서 복원 (`D.archivedOrigOrder`)
- 보관 데이터 archived 컬럼 누락 → 재접속 시 손실 → 수정
- 페이지 이탈 시 즉시 push (`beforeunload` + dirty flag)

## [0.2.0] — 2026-04-26 (플랫폼 설정 강화)

### Fixed
- `DEFAULT_PLATFORMS` 중복 `greeting` 항목 제거
- 기존 저장 데이터에 중복 greeting 자동 dedup 마이그레이션
- `addPlatform()` ID 충돌 방지 (한국어 → `___` 변환 시 dedup suffix)
- `removePlatform()` 후 `D.postedPlatforms` 잔류 정리
- Quill 1.3.6 호환: copyRichHtml 시 블록 태그 사이 공백 압축 (`>\s+<` → `><`) — 빈 줄 중복 해결

## [0.1.0] — 2026-03-15 (초기 구현)

### Added
- 단일 HTML 파일 채용공고 관리 도구
- 다중 플랫폼 지원 (그리팅·잡코리아·원티드·리멤버·프로그래머스·사람인·인크루트·인디드·링크드인)
- KO/EN 콘텐츠 분리, 섹션 관리, 공통 섹션
- 플랫폼별 복사 (HTML·RichHTML·플레인·필드 단위)
- Supabase 정규화 5개 테이블 동기화 (config·positions·common_content·position_content·posting_urls)
- localStorage + Supabase 양방향 sync (3초 debounce push)
