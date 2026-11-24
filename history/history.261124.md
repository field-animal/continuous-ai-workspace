# 변경 이력 - 2026-11-24

## (12:53 KST) - Antigravity

- **[Feat] `.env` 환경변수(`CAW_PWA_APPNAME`, `CAW_PWA_ICON`) 기반 PWA 앱 이름·아이콘 브랜딩 지원 (`v0.1.14-261124`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.14-261124` (`./VERSION`)
  - **대상**:
    - `./.env.example`, `./.gitignore`, `./assets/.gitkeep`
    - `./docker-compose.yml`
    - `./cont-init.d/50-pwa-branding.sh` (신규)
    - `./lib/common.sh`, `./scripts/install.sh`, `./bin/caw`
    - `./VERSION`, `./README.md`, `./AGENTS.md`
    - `./history/history.261124.md` (신규)
  - **내용**:
    1. `./.env.example` 및 `./docker-compose.yml`에 `CAW_PWA_APPNAME`(컨테이너 `PWA_APPNAME` 연동)과 `CAW_PWA_ICON` 환경변수를 추가하고, 커스텀 정적 자산용 `./assets:/opt/caw/assets:ro` 읽기 전용 마운트를 구성.
    2. `./cont-init.d/50-pwa-branding.sh` 독립 기동 모듈을 신설하여 `PWA_APPNAME`에 맞춘 `workbench.html`의 `apple-mobile-web-app-title` 동기화와 `CAW_PWA_ICON`(단일 PNG/SVG/ICO 파일, 표준 아이콘 6종 디렉토리, `https://` URL)의 매직 바이트·SVG XSS 패턴·해상도 검증 및 적용을 구현(미설정·오프라인·오류 시 기본 아이콘으로 안전 복원).
    3. `./lib/common.sh`, `./scripts/install.sh`, `./bin/caw doctor`에 PWA 환경변수 보안 검증(제어문자·경로 이탈·비-HTTPS 차단) 및 사전/자가 진단 항목을 추가하고, `./AGENTS.md` 기존 컨테이너 점검 항목에 `PWA_APPNAME` 승계를 반영.

## (13:16 KST) - Antigravity

- **[Feat] CAW 까마귀 엠블럼 아이콘 추가, `CAW` 기본 앱 이름 동기화 및 `assets` 접두사 정규화 보완 (`v0.1.15-261124`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.15-261124` (`./VERSION`)
  - **대상**:
    - `./assets/caw-icon.png` (신규), `./.gitignore`, `./.env.example`
    - `./docker-compose.yml`, `./cont-init.d/50-pwa-branding.sh`
    - `./lib/common.sh`, `./scripts/install.sh`, `./bin/caw`
    - `./VERSION`, `./README.md`, `./history/history.261124.md`
  - **내용**:
    1. CAW(까마귀 울음소리) 명칭에 맞춰 다크 슬레이트 배경 + 기하학 까마귀 머리 엠블럼 아이콘(`./assets/caw-icon.png`)을 생성·추가하고 `./.env.example` 기본값(`CAW_PWA_APPNAME=CAW`, `CAW_PWA_ICON=./assets/caw-icon.png`) 및 `./.gitignore` 예외 규칙을 반영.
    2. `./docker-compose.yml`, `./lib/common.sh`, `./cont-init.d/50-pwa-branding.sh`, `./bin/caw`의 `CAW_PWA_APPNAME` / `PWA_APPNAME` 기본 폴백을 `CAW`로 일관되게 동기화.
    3. 상대경로 접두사 정규화 시 `./assets`, `assets`, `./assets/` 루트 디렉토리 입력도 `/opt/caw/assets`로 안전 해석되도록 `50-pwa-branding.sh`, `scripts/install.sh`, `bin/caw`를 보완.

## (13:37 KST) - Antigravity

- **[Design] 시안 2-R(투명 배경 역동적 까마귀 머리 엠블럼) 채택 반영 (`v0.1.16-261124`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.16-261124` (`./VERSION`)
  - **대상**:
    - `./VERSION`, `./README.md`, `./bin/caw`, `./history/history.261124.md`
  - **내용**:
    1. CAW 기본 아이콘 시안을 배경색 없는 역동적 전진형 까마귀 머리 엠블럼(2-R)으로 확정하고 투명 배경 `512x512` PNG 규격(`./assets/caw-icon.png`) 기준으로 문서·버전(`v0.1.16-261124`)을 갱신.

## (14:30 KST) - Antigravity

- **[Fix] `cont-init.d/50-pwa-branding.sh` 실행 권한(`100755`) 보완 (`v0.1.17-261124`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.17-261124` (`./VERSION`)
  - **대상**:
    - `./cont-init.d/50-pwa-branding.sh` (파일 모드 `100644` -> `100755`)
    - `./VERSION`, `./README.md`, `./bin/caw`, `./history/history.261124.md`
  - **내용**:
    1. 읽기 전용 마운트(`./cont-init.d:/custom-cont-init.d:ro`)로 연결되는 `cont-init.d/50-pwa-branding.sh`에 실행 권한(`chmod +x`, Git `100755`)이 누락되어 있던 점을 수정하여 s6-overlay 초기화 시 정상 실행되도록 보완.

## (14:43 KST) - Antigravity

- **[Refactor] 추적 Compose 파일 무수정 구조화 및 `git pull` 충돌 요인 제거 (`v0.1.18-261124`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.18-261124` (`./VERSION`)
  - **대상**:
    - `./compose.mux-socket.yml` (신규)
    - `./docker-compose.yml`, `./compose.dood.yml`, `./compose.override.yml.example`
    - `./.env.example`, `./.gitignore`
    - `./lib/common.sh`
    - `./VERSION`, `./bin/caw`, `./README.md`, `./AGENTS.md`, `./history/history.261124.md`
  - **내용**:
    1. 기존 `docker-compose.yml` 내 주석 처리되어 있던 멀티플렉서 소켓 직결 블록을 독립 모듈 `./compose.mux-socket.yml`로 분리하고, `lib/common.sh`(`caw_build_compose_args`)가 `CAW_SHARE_MUX_SOCKET=true` 시 자동 결합하며 `compose.override.yml`을 최후순위로 배치하도록 개선.
    2. `./compose.dood.yml`의 호스트 Docker 바이너리·플러그인 경로를 `CAW_DOCKER_BIN`, `CAW_DOCKER_CLI_PLUGINS_DIR` 환경변수화하여 배포판별 경로 차이로 인한 수정 필요성 제거.
    3. `./docker-compose.yml` 및 `./.env.example`에 `TZ`, `CAW_SUDO_PASSWORD_HASH`(`lib/common.sh`의 작은따옴표·`$` 검증 포함)를 추가하고, `./.gitignore`에 호스트 전용 로컬 훅(`cont-init.d/9*-local*.sh`) 예외 규칙과 `./compose.override.yml.example` 확장 예시(`environment`, `labels`, `extra_hosts`, `deploy`)를 보강.
