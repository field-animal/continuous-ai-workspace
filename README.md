# CAW (Continuous AI Workspace)

**버전:** `0.1.4-261116`

**CAW (`continuous-ai-workspace`)** 는 클라이언트 기기(노트북·데스크톱)의 전원 종료, 절전 진입, 또는 기기를 소지하지 않은 채 다른 장소의 새로운 머신으로 이동하더라도 **동일한 리눅스 호스트 위에서 AI 에이전트(Google Antigravity, Claude Code)와 웹 IDE(`code-server`), 터미널 멀티플렉서(`tmux` 또는 `zellij`) 세션을 끊김 없이 이어가기 위한 범용 인프라 구성 패키지**입니다.

---

## 1. 설계 배경 및 핵심 원리

1. **호스트 SSH 2중 인증 경계 보존 및 백그라운드 연속 실행 (`CAW_SHARE_MUX_SOCKET=false` 기본)**
   - `code-server`는 브라우저 탭 종료·절전 시 내장 셸 및 확장 호스트 자원을 정리합니다.
   - 동시에 호스트 멀티플렉서 소켓이나 `docker.sock`을 컨테이너에 직접 마운트하면 `code-server` 단일 비밀번호 침해 시 호스트 OS 권한까지 노출됩니다.
   - CAW는 **기본적으로 멀티플렉서 소켓과 `docker.sock`을 컨테이너에 마운트하지 않고(`CAW_SHARE_MUX_SOCKET=false`, `CAW_ENABLE_DOOD=false`)**, 웹 IDE 내장 터미널에서 **호스트로 `ssh` 로그인(2차 인증)한 뒤 호스트 순정 멀티플렉서(`tmux` 또는 `zellij`)를 구동**하는 보안 경계를 표준으로 채택합니다.
   - 폐쇄망 단일 사용자 환경 등에서 SSH 없이 내장 터미널 소켓 직결을 원할 경우에만 `docker-compose.yml`의 주석 블록을 해제하고 `CAW_SHARE_MUX_SOCKET=true`로 선택 지정할 수 있습니다.
2. **IDE 웹 패널 <-> 터미널 CLI 양방향 대화 저장소 단일화**
   - Antigravity의 내장 가져오기(`/resume` -> `Other`)는 `IDE -> CLI` 단방향만 지원합니다.
   - CAW의 `bin/agy` 래퍼는 `--app_data_dir=antigravity` 및 현재 작업 경로(`$PWD`) 기반 `--project` 자동 매칭을 주입하여, IDE 패널과 터미널 CLI가 동일한 SQLite 대화 저장소(`~/.gemini/antigravity`)를 양방향으로 직접 공유합니다.
   - Claude Code 역시 호스트 공식 스탠드얼론 CLI(`~/.local/bin/claude`)와 확장 패널이 `~/.claude` 디렉토리를 동일 절대경로로 공유합니다.
3. **실행 계정 자동 치환 및 프록시·멀티플렉서 중립 모듈화**
   - `.env`에서 사용자·UID·GID·워크스페이스 경로를 비워 두면 현재 실행하는 사용자의 계정 정보(`id -u`, `id -g`, `$USER`, `$HOME`)로 자동 치환됩니다.
   - 호스트에 설치된 멀티플렉서(`tmux` 또는 `zellij`) 단 1종만 감지해 중복 실행을 배제하며, 아무것도 없는 클린 호스트에서는 설치 시 `1) tmux 설치 / 2) zellij 설치 / 3) 설치 안 함(none)` 선택을 제공합니다.
   - 다중 보조 워크스페이스 마운트는 표준 `compose.override.yml`(`compose.override.yml.example` 제공)로 개수 제한 없이 확장합니다.
4. **저작권 및 배포 약관 준수 (Zero Bundled Proprietary Assets)**
   - 상용 바이너리(`agy`, `claude`), `.vsix` 패키지, 포크된 컨테이너 이미지를 저장소에 일절 포함하지 않고 순수 선언형 구성(IaC)과 래퍼 스크립트만 제공합니다.

---

## 2. 디렉토리 구조

```text
continuous-ai-workspace/
├── VERSION                          # 패키지 버전 (0.1.4-261116)
├── .env.example                     # 서버별 환경변수 템플릿 (사용자·경로·멀티플렉서 중립)
├── .gitignore                       # 시크릿, 로컬 오버라이드, 상용 바이너리, 백업 커밋 차단
├── docker-compose.yml               # 코어 구성 (기본 SSH 2중 인증 경계, 소켓 직결은 주석 분리)
├── compose.override.yml.example     # [선택 템플릿] 복수 워크스페이스 및 외부 네트워크 로컬 확장
├── compose.dood.yml                 # [선택 모듈] 호스트 Docker(DooD) 연동
├── lib/
│   ├── common.sh                    # eval 없는 .env 파서, 자동 기본값 치환, 경로·시크릿·잠금 검증
│   └── multiplexer.sh               # 멀티플렉서 단일 감지, 미설치 선택 설치(정책 A) 모듈
├── cont-init.d/
│   ├── 05-cli-links.sh              # 디렉토리 마운트(/opt/caw/bin) 기반 공용 CLI 심볼릭 링크 연결
│   ├── 10-docker-gid.sh             # DooD 활성화 시 소켓 GID 동기화
│   ├── 20-extensions.sh             # 공식 갤러리 확장 멱등 자동 설치 (오프라인 방어 포함)
│   ├── 30-agent-storage.sh          # Antigravity 인증·설정 심볼릭 링크 보장
│   └── 40-multiplexer.sh            # [선택] CAW_SHARE_MUX_SOCKET=true 일 때만 소켓 직결 초기화
├── bin/
│   ├── caw                          # 보조 관리 CLI (status, unlock, clean, doctor, attach)
│   ├── agy                          # Antigravity 양방향 저장소 공유 래퍼
│   ├── claude                       # 호스트 공식 스탠드얼론 claude 위임 래퍼
│   ├── zellij                       # [선택] 소켓 직결 모드용 zellij 래퍼
│   └── tmux                         # [선택] 소켓 직결 모드용 tmux 래퍼
├── scripts/
│   ├── install.sh                   # 신규 설치 및 기존 운영 서버 전환(--adopt) 스크립트
│   └── rollback.sh                  # 백업 매니페스트 기반 1-커맨드 원복 스크립트
└── examples/
    ├── traefik-ide.yml.example      # Traefik v3 동적 라우팅 레퍼런스
    └── npm-nginx.conf.example       # Nginx Proxy Manager / 표준 Nginx 레퍼런스
```

---

## 3. 설치 및 적용 가이드

### 시나리오 A: 신규 리눅스 서버에 처음 구축 (Greenfield)

```bash
git clone <원격_저장소_URL> continuous-ai-workspace
cd continuous-ai-workspace
cp .env.example .env
chmod 600 .env
# .env 파일 내 CAW_BASE_DOMAIN, CAW_HASHED_PASSWORD(또는 CAW_PASSWORD) 등 필수 항목만 기입
# (PUID, PGID, HOST_USER, HOST_HOME, CAW_WORKSPACE_DIR 은 비워두면 현재 계정 기준으로 자동 설정됨)

# [선택] 복수의 추가 워크스페이스 디렉토리 마운트가 필요한 경우:
# cp compose.override.yml.example compose.override.yml 후 볼륨 경로 수정

# 1) 변경 전 사전 검증 (파일/컨테이너 무변경)
./scripts/install.sh --dry-run

# 2) 실제 설치 및 기동
./scripts/install.sh

# 3) 환경 자가 진단
~/.local/bin/caw doctor
```

### 시나리오 B: 기존 `code-server` 운영 서버에 무손실 전환 적용 (Brownfield / `--adopt`)

기존에 다른 Compose 프로젝트로 `code-server`를 운영 중인 서버에서도 기존 설정 디렉토리(`CAW_CONFIG_DIR` 지정)를 그대로 이어받으면서 기존 컨테이너를 `code-server-caw-backup`으로 보존 백업할 수 있습니다.

> **주의:** 현재 실행 중인 AI 에이전트 세션이 있을 때는 전환을 실행하지 마십시오(`install.sh`가 활성 `.lock`을 감지하면 안전을 위해 자동 중단합니다). 반드시 모든 에이전트 대화를 정상 종료한 뒤 호스트 셸에서 실행하십시오.

```bash
cd /path/to/continuous-ai-workspace
cp .env.example .env
chmod 600 .env
# 기존 서버의 code-server 설정 경로(CAW_CONFIG_DIR), 도메인, 인증 정보 등을 .env 에 반영 후 실행:

./scripts/install.sh --adopt --migrate-cli-sessions --dry-run
./scripts/install.sh --adopt --migrate-cli-sessions

# 문제 발생 시 언제든 즉시 이전 컨테이너와 바이너리로 원복 가능
./scripts/rollback.sh
```

---

## 4. 장소 및 기기 이동 시 표준 운영 워크플로우

### 1) 기본 보안 워크플로우 (호스트 SSH 2중 인증 경계)
1. **작업 시작**: 웹 브라우저로 `code-server` 접속 -> 내장 터미널 열기 -> `ssh <계정>@<호스트_IP>`로 호스트 로그인 -> `zellij attach -c <세션명>` 또는 `tmux new -A -s <세션명>` (편의 단축 명령 `caw attach` 사용도 동일) 진입 -> 그 안에서 `agy` 또는 `claude` 실행.
   - 호스트 OS에서 직접 동작하므로 `docker.sock`을 컨테이너에 노출하지 않아도 멀티플렉서 내부에서 호스트의 타 컨테이너 제어가 100% 가능합니다.
   - 브라우저를 닫거나 클라이언트 PC 전원을 꺼도 호스트 백그라운드에서 작업이 100% 연속 실행됩니다.
2. **다른 장소·다른 머신에서 작업 재개**: 새 머신에서 `code-server` 내장 터미널(호스트 `ssh` 로그인) 또는 외부 SSH 클라이언트로 접속해 동일한 멀티플렉서 세션에 `attach`하면 진행 중이던 화면이 그대로 복원됩니다.
3. **대화 잠금(`.lock`) 전환 규칙**:
   - 터미널 `agy` 대화를 웹 IDE 사이드바 패널로 넘겨받으려면 터미널 `agy`에서 `/exit` (또는 `/new`)로 잠금을 해제한 뒤 IDE 패널에서 엽니다.
   - 반대로 브라우저를 닫은 뒤 유휴 IDE 허브가 잡고 있는 대화를 터미널 `agy`에서 이어받으려면 `caw unlock` 실행 후 재개합니다.

---

## 5. `caw` 보조 CLI 주요 명령 요약

| 명령 | 동작 설명 |
| --- | --- |
| `caw status` | 실행 중인 `agy` / `claude` / `tmux` / `zellij` 자원 현황 및 활성 대화 `.lock` 점유 조회 |
| `caw unlock` | 브라우저 종료 후 유휴 `agy --hub` 프로세스에 `SIGTERM`을 보내 대화 잠금 즉시 반환 |
| `caw clean [--stop-claude]` | 종료된(`EXITED`) 멀티플렉서 잔여 캐시 세션 정리 (활성 세션은 절대 종료하지 않음) |
| `caw doctor` | 보안 경계 모드, 통합 인증 링크, 활성 멀티플렉서, `systemd Linger=yes` 무결성 진단 |
| `caw attach [세션명]` | 선택적 단축 명령 (`zellij attach -c` 또는 `tmux new -A -s` 원본 명령 직접 사용과 동일) |

---

## 6. 보안 및 업스트림 버전 관리 수칙

1. **시크릿 보호**: `.env` 파일은 `chmod 600` 권한이 강제되며, 평문 `CAW_PASSWORD` 대신 Argon2 해시(`CAW_HASHED_PASSWORD`) 사용을 권장합니다. 빈 비밀번호나 예시 비밀번호로는 설치가 거부됩니다(Fail-Close).
2. **2중 인증 경계 유지**: 기본값(`CAW_SHARE_MUX_SOCKET=false`, `CAW_ENABLE_DOOD=false`)을 유지하여 컨테이너 침해가 호스트 OS 침해로 직결되지 않도록 보호하십시오.
3. **네트워크 최소 노출**: `CAW_BIND_ADDR` 기본값은 `127.0.0.1`입니다. 리버스 프록시가 별도 서버에서 동작할 때만 내부망 사설 IP로 변경하고 공인 인터페이스(`0.0.0.0`) 직접 노출은 피하십시오.
4. **이미지 태그 고정**: 예기치 않은 업스트림 변경 방지를 위해 `:latest` 대신 검증된 버전 태그(`CAW_IMAGE_TAG=4.145.2`)를 고정합니다.
