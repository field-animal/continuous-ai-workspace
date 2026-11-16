# 변경 이력 - 2026-11-13

## (19:42 KST) - Antigravity

- **[Infra] 범용 연속 AI 작업 환경 구축 패키지 `CAW (continuous-ai-workspace)` 초기 구성**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.0-261113` (`./VERSION`)
  - **대상**:
    - `./VERSION`, `./.gitignore`, `./.env.example`
    - `./docker-compose.yml`, `./compose.dood.yml`
    - `./lib/common.sh`
    - `./cont-init.d/10-docker-gid.sh`, `./cont-init.d/20-extensions.sh`, `./cont-init.d/30-agent-storage.sh`
    - `./bin/caw`, `./bin/agy`, `./bin/claude`, `./bin/zellij`
    - `./scripts/install.sh`, `./scripts/rollback.sh`
    - `./examples/traefik-ide.yml.example`, `./examples/npm-nginx.conf.example`, `./README.md`
  - **내용**:
    1. **독립 모듈형 범용 환경 패키지 설계**:
       - 상용 바이너리·VSIX·포크 이미지를 일절 포함하지 않고, 버전 고정(`lscr.io/linuxserver/code-server:4.145.2`) Compose 선언 및 단일 책임 셸 모듈만으로 구성.
       - DooD(`./compose.dood.yml`) 및 컨테이너 기동 초기화(`./cont-init.d/10~30`)를 독립 분리하여 기능별 선택적 제외 가능하도록 구현.
    2. **장소·기기 무관 백그라운드 연속 실행 및 양방향 세션 저장소 통합**:
       - `bin/agy` 래퍼에서 `--app_data_dir=antigravity` 및 `$PWD` 기반 `--project` 자동 매칭을 수행하고 인증 토큰 심볼릭 링크를 연결하여 웹 IDE 패널과 터미널 CLI 간 양방향 대화 이어가기 구현.
       - 확장 내부 비공개 경로 의존을 제거하고 호스트 공식 스탠드얼론 `claude` CLI 위임 래퍼(`./bin/claude`) 적용.
    3. **보안 강화 및 기존 운영 서버 무손실 전환(`--adopt`) / 원복(`rollback.sh`) 지원**:
       - `./lib/common.sh`에 `eval` 없는 화이트리스트 `.env` 파서, 경로 경계 이탈 검증(`caw_validate_path`), 빈 비밀번호 기동 차단(`caw_verify_secrets`, Fail-Close), 활성 `.lock` 점유 시 강제 교체 차단(`caw_check_no_active_locks`), 기본 `127.0.0.1` 바인딩 적용.
       - `./scripts/install.sh`(`--dry-run`, `--adopt`, `--migrate-cli-sessions`) 및 `.caw-state/manifest.env` 기반 `./scripts/rollback.sh` 제공, 프록시 레퍼런스(`./examples/`) 문서화.

## (20:14 KST) - Antigravity

- **[Refactor] 개인 환경 종속 정보 전수 제거, 실행 계정 자동 치환 및 표준 오버라이드 전환**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.1-261113` (`./VERSION`, 커밋 해시: `511bd60`)
  - **대상**:
    - `./.env.example`, `./.gitignore`, `./docker-compose.yml`, `./compose.override.yml.example`
    - `./lib/common.sh`, `./scripts/install.sh`, `./bin/caw`, `./bin/zellij`, `./README.md`
  - **내용**:
    1. **실행 사용자 자동 치환**:
       - `PUID`, `PGID`, `HOST_USER`, `HOST_HOME`, `CAW_CONFIG_DIR`, `CAW_WORKSPACE_DIR` 미선언(빈 값) 시 현재 실행 계정 정보로 자동 치환되도록 개선하고 기본 세션명을 `caw`로 일반화.
    2. **복수 워크스페이스 확장을 위한 표준 오버라이드 도입**:
       - 개수 제한 없는 볼륨 마운트와 `docker compose up -d` 자동 병합을 지원하는 `./compose.override.yml.example` 템플릿 도입(`compose.override.yml`은 `./.gitignore` 처리 및 `caw_build_compose_args` 자동 인식).

## (21:06 KST) - Antigravity

- **[Feat/Refactor] 멀티플렉서 완전 중립화(`zellij`·`tmux`·`none` 단일 선택) 및 미설치 선택 설치(정책 A) 구현**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.2-261113` (`./VERSION`, 커밋 해시: `a536b0d`)
  - **대상**:
    - `./.env.example`, `./docker-compose.yml`
    - `./lib/common.sh`, `./lib/multiplexer.sh` (신규)
    - `./cont-init.d/30-agent-storage.sh`, `./cont-init.d/40-multiplexer.sh` (신규)
    - `./bin/tmux` (신규), `./bin/zellij`, `./bin/caw`
    - `./scripts/install.sh`, `./scripts/rollback.sh`, `./README.md`
  - **내용**:
    1. `CAW_MULTIPLEXER=auto|zellij|tmux|none` 옵션을 도입하여 호스트 기설치 도구 단 1종만 활성화하고 중복 실행 및 충돌을 원천 차단.
    2. 호스트에 멀티플렉서가 없을 때 대화형 선택 설치 프롬프트(`tmux` / `zellij` / `none`, `./lib/multiplexer.sh`) 제공 및 비대화형 실행 시 `none` 모드 정상 기동 보장.

## (21:40 KST) - Antigravity

- **[Security/Refactor] 호스트 SSH 2중 인증 경계 기본화 및 멀티플렉서 소켓 직결 주석 격리 (`CAW_SHARE_MUX_SOCKET=false`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.3-261113` (`./VERSION`, 커밋 해시: `1f792bf`)
  - **대상**:
    - `./docker-compose.yml`, `./.env.example`, `./lib/common.sh`
    - `./cont-init.d/40-multiplexer.sh`, `./scripts/install.sh`, `./bin/caw`, `./README.md`
  - **내용**:
    1. `./docker-compose.yml`에서 멀티플렉서 유닉스 소켓 볼륨 및 소켓 환경변수 블록을 선택용 주석으로 전환하고 `CAW_SHARE_MUX_SOCKET=false`를 기본값으로 설정하여, 내장 터미널에서 호스트 SSH 2차 인증을 거치도록 보안 경계 강화.
    2. 기본 모드(`false`)에서는 호스트 순정 멀티플렉서 환경을 그대로 보존하며, 폐쇄망 등에서 필요 시 주석 해제 및 `true` 설정으로 소켓 직결 선택 활성화 지원.
