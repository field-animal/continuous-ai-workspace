# AGENTS.md - CAW (Continuous AI Workspace) AI 에이전트 자동 구축 규약

본 문서는 AI 에이전트(Google Antigravity, Claude Code 등)가 대상 리눅스 호스트의 환경을 스스로 실사하여 **신규 설치(Greenfield)** 또는 **기존 서버 무손실 전환(Brownfield `--adopt`)**을 일관되고 안전하게 수행하기 위한 표준 작업 지침입니다.

## 사용자 호출용 단일 공통 프롬프트 예시

어느 호스트에서든 아래 한 문장으로 에이전트에게 구축을 지시할 수 있습니다.

```text
이 저장소의 AGENTS.md 절차에 따라 현재 서버(외부 접속 도메인: <도메인명>) 환경을 실사하고 CAW 구축을 진행해 줘.
```

---

## 1. 절대 안전 및 보안 수칙 (Hard Rules)

1. **시크릿 채팅 노출 및 평문 출력 금지**
   - 사용자에게 채팅창으로 비밀번호(`CAW_PASSWORD`, `CAW_HASHED_PASSWORD`, `CAW_SUDO_PASSWORD`)를 입력받지 마십시오.
   - `.env` 파일의 비밀번호 항목은 공란으로 구성한 뒤 사용자가 에디터·터미널에서 직접 기입하게 하거나, 기존 운영 컨테이너의 `.env` 파일이 서버에 이미 존재할 경우 값을 화면(표준출력)에 노출하지 않고 파일 간 매핑 여부만 확인하십시오.
   - Argon2 해시(`$argon2id$...`)를 사용할 경우 반드시 작은따옴표(`'...'`)로 감싸야 합니다.
2. **자체 종료(Self-Termination) 원천 금지**
   - 현재 에이전트 프로세스가 **기존 `code-server` 컨테이너 내부(`/.dockerenv` 존재)**에서 실행 중이거나, 호스트 `~/.gemini/*/presence`에 활성 대화 잠금(`.lock`)을 점유한 상태라면 **절대 실제 기동(`./scripts/install.sh`의 `--dry-run` 제외 실행)을 직접 호출하지 마십시오.**
   - 이 경우 **4단계(`--dry-run` 사전 검증)**까지만 완료한 뒤, 사용자가 모든 에이전트를 종료하고 **외부 직접 SSH 터미널**에서 실행할 최종 명령어만 안내하고 멈추십시오.
3. **기본 보안 경계 임의 완화 금지**
   - 사용자의 명시적 지시가 없는 한 `CAW_SHARE_MUX_SOCKET=false`(호스트 SSH 2중 인증 경계), `CAW_ENABLE_DOOD=false`(도커 소켓 미마운트), 최소 노출 바인딩 원칙을 그대로 유지하십시오.

---

## 2. 표준 5단계 구축 프로토콜

### [1단계] 대상 호스트 및 프록시 환경 실사 (Read-Only)
파일을 생성·수정하기 전에 아래 항목을 먼저 점검하여 사용자에게 요약 보고합니다.

1. **호스트 런타임 점검 (`README.md`의 `Required` 대조)**
   - OS 및 `loginctl show-user "$USER" -p Linger` 상태
   - `docker compose version`, 호스트 `sshd` 활성 여부, 기본 도구(`tar`, `awk`, `realpath`, `sha256sum`, `lsof`, `curl`) 유무
   - 기설치 멀티플렉서(`zellij`, `tmux`) 및 스탠드얼론 `~/.local/bin/claude` 존재 여부
2. **기존 `code-server` 컨테이너 유무 및 마운트 구조 점검**
   - `docker ps -a`로 기존 `code-server`(또는 `8443` 포트 사용 컨테이너) 존재 여부 확인
   - 기존 컨테이너가 존재할 경우 `docker inspect`로 아래 4가지를 추출:
     - `/config` 마운트 원본 호스트 경로 (`CAW_CONFIG_DIR` 승계 대상)
     - `/config/.gemini`가 호스트 홈(`~/.gemini`)으로 분리 마운트되어 있는지 여부 (미분리 상태로 `/config/.gemini` 내부에만 데이터가 있으면 덮어 마운트 시 가려지므로 사전 복사 필요)
     - 마운트된 워크스페이스 경로 목록 (1개인지, 2개 이상 다중 경로인지 확인)
     - 기존 `PROXY_DOMAIN`, `CODE_SERVER_COOKIE_SUFFIX`, `AGY_ALLOWED_DOMAINS` 설정값
3. **리버스 프록시 연동 구조 점검**
   - 프록시(Traefik / NPM / Nginx)가 호스트 루프백(`127.0.0.1:8443`)으로 전달하는지, 별도 Docker 브리지에서 호스트 사설 IP(예: `192.168.x.x:8443`)로 전달하는지 확인 (`127.0.0.1` 불일치 시 `502 Bad Gateway` 발생 방지)
   - 와일드카드 TLS(`*.<도메인>`) 및 포트 프록시(`ide-<포트>.<도메인>`) 구간의 `X-Frame-Options` 제외 조건 충족 여부 확인

### [2단계] 구축 모드 판별 및 계획 확인
실사 결과를 바탕으로 적용 모드를 판별하고 사용자의 확인을 받습니다.
- **신규 구축(Greenfield)**: 기존 컨테이너 없음 -> 기본 `./scripts/install.sh` 적용
- **무손실 전환(Brownfield)**: 기존 컨테이너 존재 -> `./scripts/install.sh --adopt` 적용 (호스트 `~/.gemini/antigravity-cli/conversations`에 기존 단독 CLI 대화가 있으면 `--migrate-cli-sessions` 추가 여부 확인)

### [3단계] `.env` 및 선택적 `compose.override.yml` 구성
1. `cp .env.example .env && chmod 600 .env` 실행
2. `PUID`, `PGID`, `HOST_USER`, `HOST_HOME`은 빈 값으로 유지(실행 계정 자동 치환)하고, 1단계에서 파악한 아래 항목을 기입합니다:
   - `CAW_BIND_ADDR`: 동일 호스트 루프백 프록시면 `127.0.0.1`, 브리지 컨테이너 프록시면 해당 호스트의 내부 사설 인터페이스 IP
   - `CAW_BASE_DOMAIN` 및 `CAW_PROXY_DOMAIN_TEMPLATE=ide-{{port}}.<도메인>`
   - 기존 서버 승계 시 `CAW_CONFIG_DIR`, `CAW_COOKIE_SUFFIX`, `CAW_WORKSPACE_DIR` 일치
3. 워크스페이스 마운트 대상이 2개 이상이거나 외부 프록시 브리지 네트워크에 직접 연결해야 하는 경우에만 `cp compose.override.yml.example compose.override.yml` 후 경로·네트워크를 반영합니다.
4. 비밀번호(`CAW_HASHED_PASSWORD` 또는 `CAW_PASSWORD`)가 비어 있으면 사용자에게 직접 `.env`에 기입하도록 안내합니다.

### [4단계] 사전 검증 (`--dry-run`)
비밀번호 설정이 확인되면 실제 변경이 없는 드라이런 검증을 반드시 먼저 통과시킵니다.

```bash
# 신규 서버일 경우
./scripts/install.sh --dry-run

# 기존 컨테이너 전환 서버일 경우
./scripts/install.sh --adopt --migrate-cli-sessions --dry-run
```

### [5단계] 최종 적용 및 사후 무결성 검증
- **현재 에이전트가 기존 `code-server` 내부이거나 활성 `.lock`을 점유 중인 경우**:
  직접 실행을 멈추고 사용자에게 **"모든 에이전트 종료 후 외부 직접 SSH 터미널에서 실행할 명령어"**와 이상 발생 시 즉시 원복하는 **`./scripts/rollback.sh`** 명령어를 함께 안내합니다.
- **현재 에이전트가 외부 독립 호스트 셸이며 잠금 충돌이 없는 경우**:
  사용자 승인 하에 설치 스크립트를 실행한 뒤 아래 항목을 검증하고 결과를 보고합니다:
  1. `~/.local/bin/caw doctor` 전 항목 `[PASS]` 여부
  2. `docker ps`에서 `code-server` 정상 기동 상태 확인
  3. 실패 또는 오동작 감지 시 즉시 `./scripts/rollback.sh`로 도입 전 원본 상태(컨테이너·바이너리·세션 DB 분리 원형) 복구 수행
