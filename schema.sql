-- ════════════════════════════════════════════════════════════════
-- jobpost — 채용공고 관리 도구 (v0.8.0) Supabase 초기 스키마
-- 새 프로젝트에서 1회 실행하면 즉시 동작 가능
-- 재실행 안전 (idempotent: IF NOT EXISTS + DROP POLICY IF EXISTS)
-- ════════════════════════════════════════════════════════════════

-- 1) 앱 설정 (섹션·플랫폼·줄바꿈·보관 목록) — 단일 row
CREATE TABLE IF NOT EXISTS config (
  id          text PRIMARY KEY DEFAULT 'default',
  sections    jsonb,
  platforms   jsonb,
  line_breaks jsonb,
  archived    jsonb DEFAULT '[]'::jsonb,
  updated_at  timestamptz DEFAULT now()
);

-- 2) 포지션 목록 + 상태 (is_archived 로 활성/보관 통합 관리)
-- metadata: 직군·고용형태·경력·연봉·마감일·근무지 등 메타필드 (index.html 메타데이터 카드와 동기화)
CREATE TABLE IF NOT EXISTS positions (
  name        text PRIMARY KEY,
  job_title   text,
  lang        text DEFAULT 'ko',
  status      text DEFAULT 'draft',
  sort_order  int  DEFAULT 0,
  is_archived boolean DEFAULT false,
  metadata    jsonb DEFAULT '{}'::jsonb,
  updated_at  timestamptz DEFAULT now()
);
-- 기존 설치(v0.7.x 이하)에서 재실행 시 metadata 컬럼 추가 (idempotent)
ALTER TABLE positions ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb;

-- 3) 공통 데이터 (KO/EN × 섹션)
CREATE TABLE IF NOT EXISTS common_content (
  lang        text NOT NULL,
  section_key text NOT NULL,
  content     text,
  updated_at  timestamptz DEFAULT now(),
  PRIMARY KEY (lang, section_key)
);

-- 4) 포지션별 데이터 (포지션 × KO/EN × 섹션)
-- ON UPDATE CASCADE: positions.name 변경 시 자식 자동 갱신 (cascade rename)
CREATE TABLE IF NOT EXISTS position_content (
  position_name text NOT NULL REFERENCES positions(name) ON UPDATE CASCADE ON DELETE CASCADE,
  lang          text NOT NULL,
  section_key   text NOT NULL,
  content       text,
  updated_at    timestamptz DEFAULT now(),
  PRIMARY KEY (position_name, lang, section_key)
);

-- 5) 포지션별 플랫폼 게시 현황
CREATE TABLE IF NOT EXISTS posting_urls (
  position_name text NOT NULL REFERENCES positions(name) ON UPDATE CASCADE ON DELETE CASCADE,
  platform_id   text NOT NULL,
  url           text,
  updated_at    timestamptz DEFAULT now(),
  PRIMARY KEY (position_name, platform_id)
);

-- 6) 자동·수동 스냅샷 백업 (recruit_ prefix: 타 프로젝트 충돌 방지)
CREATE TABLE IF NOT EXISTS recruit_snapshots (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  label      text NOT NULL,
  data       jsonb NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_recruit_snapshots_created_at
  ON recruit_snapshots (created_at DESC);

-- 7) 활동 로그 (push/pull/rename/connect 등 모든 이벤트)
CREATE TABLE IF NOT EXISTS recruit_activity_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ts         timestamptz DEFAULT now(),
  event_type text NOT NULL,
  level      text DEFAULT 'info',
  message    text,
  context    jsonb DEFAULT '{}'::jsonb,
  client_id  text
);
CREATE INDEX IF NOT EXISTS idx_recruit_activity_ts
  ON recruit_activity_log (ts DESC);
CREATE INDEX IF NOT EXISTS idx_recruit_activity_level
  ON recruit_activity_log (level) WHERE level IN ('warn','error');

-- ════════════════════════════════════════════════════════════════
-- RLS (기본: Allow all — 단독·소수 사용 가정)
-- 다중 사용자·외부 공개 시 별도 인증 + 사용자별 정책으로 교체 필요
-- ════════════════════════════════════════════════════════════════
ALTER TABLE config               ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE common_content       ENABLE ROW LEVEL SECURITY;
ALTER TABLE position_content     ENABLE ROW LEVEL SECURITY;
ALTER TABLE posting_urls         ENABLE ROW LEVEL SECURITY;
ALTER TABLE recruit_snapshots    ENABLE ROW LEVEL SECURITY;
ALTER TABLE recruit_activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all" ON config;
DROP POLICY IF EXISTS "Allow all" ON positions;
DROP POLICY IF EXISTS "Allow all" ON common_content;
DROP POLICY IF EXISTS "Allow all" ON position_content;
DROP POLICY IF EXISTS "Allow all" ON posting_urls;
DROP POLICY IF EXISTS "Allow all" ON recruit_snapshots;
DROP POLICY IF EXISTS "Allow all" ON recruit_activity_log;

CREATE POLICY "Allow all" ON config               FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON positions            FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON common_content       FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON position_content     FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON posting_urls         FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON recruit_snapshots    FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON recruit_activity_log FOR ALL USING (true) WITH CHECK (true);

-- ════════════════════════════════════════════════════════════════
-- 스키마 캐시 즉시 갱신 (PostgREST)
-- ════════════════════════════════════════════════════════════════
NOTIFY pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════
-- 검증 — 7개 테이블 모두 생성됐는지 확인
-- 기대값: 7개 row 출력 (각 테이블 + 컬럼 수)
-- ════════════════════════════════════════════════════════════════
SELECT table_name,
       (SELECT count(*) FROM information_schema.columns
        WHERE table_name = t.table_name AND table_schema='public') AS columns
FROM information_schema.tables t
WHERE table_schema='public'
  AND table_name IN ('config','positions','common_content',
                     'position_content','posting_urls',
                     'recruit_snapshots','recruit_activity_log')
ORDER BY table_name;
