# 변경 이력 - 2026-11-16

## (10:23 KST) - Antigravity

- **[Fix/Refactor] 코드 리뷰 High·Medium 결함 5건 패치 및 `python3` 의존성 제거 (`v0.1.4-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.4-261116` (`./VERSION`, 커밋 해시: `4fa496e`)
  - **대상**:
    - `./VERSION`, `./.env.example`, `./docker-compose.yml`, `./lib/common.sh`
    - `./cont-init.d/05-cli-links.sh` (신규), `./cont-init.d/20-extensions.sh`
    - `./bin/agy`, `./bin/caw`, `./scripts/install.sh`, `./README.md`
  - **내용**:
    1. 오프라인·갤러리 일시 장애로 확장 설치가 실패하더라도 경고 로그 출력 후 코어 `code-server` 기동은 계속 진행되도록 방어 처리(`./cont-init.d/20-extensions.sh`).
    2. Argon2 해시 작은따옴표(`'...'`)·`$$` 이스케이프 해석 일치 및 비보호 `$`·손상 해시 Fail-Close 차단(`./lib/common.sh`), `.env` 심볼릭 링크 방어 추가(`./scripts/install.sh`).
    3. `caw status` 및 `caw unlock` 조회 대상을 `ps -u $(id -u)`로 한정하여 타 사용자 프로세스 간섭 차단(`./bin/caw`).
    4. 단일 파일 마운트를 `/opt/caw/bin:ro` 디렉토리 마운트 + 초기화 심볼릭 링크(`./cont-init.d/05-cli-links.sh`)로 전환해 `git pull` 즉시 반영 보장.
    5. `./bin/agy` 내 프로젝트 매칭을 순수 `awk`·`bash`(`%XX` UTF-8 디코딩 포함)로 교체하여 파이썬 의존성 완전 제거 및 값 소비 플래그 파싱 개선.

## (10:48 KST) - Antigravity

- **[Fix/Security] 2차 검증 잔여 이슈 해소 및 공급망 무결성 보강 (`v0.1.5-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.5-261116` (`./VERSION`, 커밋 해시: `a9b8522`)
  - **대상**:
    - `./VERSION`, `./README.md`, `./.env.example`
    - `./lib/common.sh`, `./lib/multiplexer.sh`
    - `./bin/caw`, `./bin/zellij`, `./bin/tmux`
    - `./scripts/install.sh`, `./scripts/rollback.sh`, `./examples/npm-nginx.conf.example`
  - **내용**:
    1. `caw_load_env_file`에 미설정 변수 전용 적재 모드(`only_if_unset=1`)를 추가하고 호스트 셸 CLI 실행 시 패키지 `.env` 설정을 자동 적재하도록 개선.
    2. Nginx `map` 분기로 메인 도메인에만 `X-Frame-Options: SAMEORIGIN` 부여, `caw` 링크 시 기존 동명 파일 백업·원복 추가.
    3. `zellij` 자동 다운로드 버전을 `v0.45.1`로 고정하고 압축 해제 전 공식 SHA-256 체크섬(`sha256sum -c`) 무결성 검사 강제 적용.

## (13:54 KST) - Antigravity

- **[Feat/Fix] 최초 도입 전 에이전트 DB·세션 원본 백업 및 중도 실패 원자적 재분리 복구 구현 (`v0.1.6-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.6-261116` (`./VERSION`, 커밋 해시: `a9e0666`)
  - **대상**:
    - `./lib/backup.sh` (신규)
    - `./scripts/install.sh`, `./scripts/rollback.sh`
    - `./VERSION`, `./bin/caw`, `./README.md`
  - **내용**:
    1. 변경 시작 전 `~/.gemini/{antigravity,antigravity-cli}` 원본 전체를 `.caw-state/pre-caw-gemini.tar.gz`(`0600`)로 1회 보관하고, 롤백 시 `tar -tzf` 무결성 확인 후 도입 이전 분리 상태로 복원(`./lib/backup.sh`, 장기 운영 후 철거용 `--keep-sessions` 지원).
    2. 매니페스트 선행 기록(`save_manifest`) 및 타 서버·타 경로 이관 시 바이너리 DB 경로 제약·심볼릭 링크 우회 지침 문서화.

## (14:19 KST) - Antigravity

- **[Feat/Fix] 이질적 기존 컨테이너 마운트·포트 사전 검증 및 정지 백업(Cold Backup) 순서 반영 (`v0.1.7-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.7-261116` (`./VERSION`, 커밋 해시: `1ea9331`)
  - **대상**:
    - `./lib/preflight.sh` (신규), `./scripts/install.sh`
    - `./VERSION`, `./bin/caw`, `./README.md`
  - **내용**:
    1. 타 컨테이너 포트 점유 차단(`caw_check_port_conflict`) 및 기존 컨테이너 내부 미분리 `/config/.gemini` 가려짐 차단(`caw_inspect_adopt_compatibility`) 모듈 추가.
    2. 기존 컨테이너를 먼저 정상 종료시켜 SQLite WAL 플러시를 완료한 뒤 정지 백업(`pre-caw-gemini.tar.gz`)을 수행하도록 실행 순서 재배치.

## (14:30 KST) - Antigravity

- **[Docs] `README.md` 서두에 `Required (필수 환경 요구사항)` 섹션 신설 (`v0.1.8-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.8-261116` (`./VERSION`, 커밋 해시: `4fd9030`)
  - **대상**: `./README.md`, `./VERSION`, `./bin/caw`
  - **내용**:
    1. 호스트 런타임(`systemd` Linger, Docker Compose v2, `sshd`), 리버스 프록시 격리 및 와일드카드 TLS·포트 프록시 구간 `X-Frame-Options` 제외 요건, `--adopt` 시 외부 SSH 실행 조건을 서두 `Required` 섹션으로 정리.

## (14:44 KST) - Antigravity

- **[Docs] 타 호스트 AI 에이전트 자동 구축 표준 규약 `AGENTS.md` 내장 (`v0.1.9-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.9-261116` (`./VERSION`, 커밋 해시: `3b9d981`)
  - **대상**: `./AGENTS.md` (신규), `./VERSION`, `./bin/caw`, `./README.md`
  - **내용**:
    1. 단일 공통 프롬프트 1개로 신규 설치와 `--adopt` 전환을 자동 분기·수행하도록 시크릿 비노출 수칙, 자체 종료 방지 규칙, 5단계 표준 구축 프로토콜을 담은 `./AGENTS.md` 작성.

## (14:50 KST) - Antigravity

- **[Docs/Chore] 변경 이력 문서를 패키지 내부 `./history/` 상대경로 체계로 일원화 (`v0.1.10-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.10-261116` (`./VERSION`)
  - **대상**:
    - `./history/history.261113.md` (신규), `./history/history.261116.md` (신규)
    - `./VERSION`, `./bin/caw`, `./README.md`
  - **내용**:
    1. 호스트 계정명 노출을 원천 차단하고 타 호스트 복제 시에도 버전별 변경 이력을 함께 추적할 수 있도록 패키지 내부 `./history/` 디렉토리로 분리하여 모든 경로를 프로젝트 루트 상대경로(`./...`)로 통일.

## (15:26 KST) - Antigravity

- **[Docs] 경로 분기 서버 가용 범위 명시 및 아키텍처 `FAQ.md` 문서 분리 신설 (`v0.1.11-261116`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.11-261116` (`./VERSION`)
  - **대상**:
    - `./FAQ.md` (신규)
    - `./README.md`, `./AGENTS.md`, `./VERSION`, `./bin/caw`
  - **내용**:
    1. `./README.md`의 `Required` 및 `./AGENTS.md`에 서브도메인 미사용(경로 분기 `/ide/`) 서버에서의 정상 가용 범위(`code-server` 본체, 호스트 SSH 멀티플렉서, 터미널 `agy`·`claude` CLI, Claude 사이드바 패널)와 제한 대상(Antigravity 사이드바 GUI 패널 1종)을 구분 명시.
    2. 와일드카드 서브도메인이 필요한 2단계 기술적 사유, `agy --hub`의 실제 실행 주체(CLI 동기화용이 아닌 IDE 확장 전용 백엔드 웹 서버)와 파일시스템 기반 세션 공유 원리, 2중 인증 경계 도커 제어 워크플로우를 `./FAQ.md`로 독립 관리.
