# CAW (Continuous AI Workspace)

**버전:** `0.1.2-261113`

**CAW (`continuous-ai-workspace`)** 는 클라이언트 기기(노트북·데스크톱)의 전원 종료, 절전 진입, 또는 기기를 소지하지 않은 채 다른 장소의 새로운 머신으로 이동하더라도 **동일한 리눅스 호스트 위에서 AI 에이전트(Google Antigravity, Claude Code)와 웹 IDE(`code-server`), 터미널 멀티플렉서(`tmux` 또는 `zellij`) 세션을 끊김 없이 이어가기 위한 범용 인프라 구성 패키지**입니다.

---

## 1. 설계 배경 및 핵심 원리

1. **브라우저 종료 시 백그라운드 작업 단절 해결 (`caw attach` - `tmux` / `zellij` 단일 연동)**
   - `code-server`는 브라우저 탭 정상 종료 시 즉시(`0초`), 절전·네트워크 단절 후 재접속 시 단축 유예(`5분`~`3시간`) 후 확장 호스트 및 일반 내장 셸 자원을 정리합니다.
   - CAW는 호스트에 설치된 멀티플렉서(`tmux` 또는 `zellij`) **단 1종만** 활성화하여 중복 실행을 원천 배제하고, 호스트와 컨테이너 내장 터미널이 동일한 공용 소켓 디렉토리(`CAW_MUX_SOCKET_DIR`, 권한 `0700` - `TMUX_TMPDIR` 및 `ZELLIJ_SOCKET_DIR`)를 바라보게 구성합니다.
   - 멀티플렉서가 전혀 없는 클린 호스트에서는 설치 시 대화형으로 `1) tmux 설치 / 2) zellij 설치 / 3) 설치 안 함(none)`을 선택할 수 있습니다.
2. **IDE 웹 패널 <-> 터미널 CLI 양방향 대화 저장소 단일화**
   - Antigravity의 내장 가져오기(`/resume` -> `Other`)는 `IDE -> CLI` 단방향만 지원합니다.
   - CAW의 `bin/agy` 래퍼는 `--app_data_dir=antigravity` 및 현재 작업 경로(`$PWD`) 기반 `--project` 자동 매칭을 주입하여, IDE 패널과 터미널 CLI가 동일한 SQLite 대화 저장소(`~/.gemini/antigravity`)를 양방향으로 직접 공유합니다.
   - Claude Code 역시 호스트 공식 스탠드얼론 CLI(`~/.local/bin/claude`)와 확장 패널이 `~/.claude` 디렉토리를 동일 절대경로로 공유합니다.
3. **실행 계정 자동 치환 및 프록시·멀티플렉서 중립 모듈화**
   - `.env`에서 사용자·UID·GID·워크스페이스·소켓 경로를 비워 두면 현재 실행하는 사용자의 계정 정보(`id -u`, `id -g`, `$USER`, `$HOME`)로 자동 치환됩니다.
   - 코어 컨테이너는 기본적으로 `127.0.0.1:8443`에만 바인딩되며, Traefik·Nginx Proxy Manager(NPM)·표준 Nginx 어느 프록시와도 결합할 수 있습니다(`examples/` 참조).
   - 다중 보조 워크스페이스나 외부 프록시 네트워크 결합은 표준 `compose.override.yml`(`compose.override.yml.example` 제공)로 개수 제한 없이 확장하며, Docker 소켓 연동(`compose.dood.yml`)과 초기화 스크립트(`cont-init.d/10~40`) 역시 독립 분리되어 있습니다.
4. **저작권 및 배포 약관 준수 (Zero Bundled Proprietary Assets)**
   - 상용 바이너리(`agy`, `claude`), `.vsix` 패키지, 포크된 컨테이너 이미지를 저장소에 일절 포함하지 않고 순수 선언형 구성(IaC)과 래퍼 스크립트만 제공합니다.

---

## 2. 디렉토리 구조

```text
continuous-ai-workspace/
├── VERSION                          # 패키지 버전 (0.1.2-261113)
├── .env.example                     # 서버별 환경변수 템플릿 (사용자·경로·멀티플렉서 중립)
├── .gitignore                       # 시크릿, 로컬 오버라이드, 상용 바이너리, 백업 커밋 차단
├── docker-compose.yml               # 코어 code-server 및 세션/소켓 공유 구성
├── compose.override.yml.example     # [선택 템플릿] 복수 워크스페이스 및 외부 네트워크 로컬 확장
├── compose.dood.yml                 # [선택 모듈] 호스트 Docker(DooD) 연동
├── lib/
│   ├── common.sh                    # eval 없는 .env 파서, 자동 기본값 치환, 경로·시크릿·잠금 검증
│   └── multiplexer.sh               # 멀티플렉서 단일 감지, 미설치 선택 설치(정책 A) 모듈
├── cont-init.d/
│   ├── 10-docker-gid.sh             # DooD 활성화 시 소켓 GID 동기화
│   ├── 20-extensions.sh             # 공식 갤러리 확장 멱등 자동 설치
│   ├── 30-agent-storage.sh          # Antigravity 인증·설정 심볼릭 링크 보장
│   └── 40-multiplexer.sh            # 선택된 단일 멀티플렉서 소켓(0700) 및 클라이언트 초기화
├── bin/
│   ├── caw                          # 통합 관리 CLI (attach, status, unlock, clean, doctor)
│   ├── agy                          # Antigravity 양방향 저장소 공유 래퍼
│   ├── claude                       # 호스트 공식 스탠드얼론 claude 위임 래퍼
│   ├── zellij                       # zellij 공유 소켓 고정 및 버전 일치 래퍼
│   └── tmux                         # tmux 공유 소켓(TMUX_TMPDIR) 고정 래퍼
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
# (CAW_MULTIPLEXER=auto 기본값 유지 시 호스트의 tmux 또는 zellij 를 자동 감지하며, 없을 경우 설치 여부를 질문함)

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
# 기존 서버의 code-server 설정 경로(CAW_CONFIG_DIR), 도메인, 인증 정보 등을 .env 에 반영하고
# 복수 워크스페이스 마운트가 필요하면 compose.override.yml 에 추가한 뒤 실행:

# 1) 드라이런 검증
./scripts/install.sh --adopt --migrate-cli-sessions --dry-run

# 2) 기존 컨테이너 백업 보존 + CLI 대화 통합 + 신규 스택 기동
./scripts/install.sh --adopt --migrate-cli-sessions

# 문제 발생 시 언제든 즉시 이전 컨테이너와 바이너리로 원복 가능
./scripts/rollback.sh
```

---

## 4. 장소 및 기기 이동 시 표준 운영 워크플로우

### 1) 연속 실행 보장 규칙
- **IDE 사이드바 패널 작업**: 브라우저를 닫거나 절전 전환 시 `code-server` 연결 해제 정책에 의해 진행 중인 스트리밍 작업이 중단될 수 있습니다. 단, 저장된 대화 기록 자체는 유지됩니다.
- **터미널 패널(`tmux` / `zellij`) 작업**: `code-server` 내장 터미널이든 외부 SSH이든 먼저 `caw attach` (선택된 멀티플렉서에 따라 `tmux new-session -A -s caw` 또는 `zellij attach -c caw` 자동 실행)로 진입한 뒤 그 안에서 `agy` 또는 `claude`를 실행하면, **브라우저를 닫거나 클라이언트 PC 전원을 꺼도 작업이 호스트 백그라운드에서 100% 연속 실행**됩니다.

### 2) 장소/기기 이동 시 충돌 방지 및 재개 절차
SQLite 데이터베이스 손상 방지를 위해 Antigravity는 활성 대화마다 배타적 커널 잠금(`presence/<uuid>.lock`)을 유지합니다.

1. **이동 출발 전 (기기 A - 사무실 등)**
   - **IDE 패널에서 대화 중이었다면**: 브라우저 탭을 닫고, 이동 후 터미널에서 이어갈 예정이면 `caw unlock`으로 유휴 IDE 허브 잠금을 반환합니다.
   - **터미널(멀티플렉서 세션)에서 작업 중이었다면**: 에이전트 작업을 그대로 켜 둔 채 멀티플렉서만 분리(`tmux`: `Ctrl+b` -> `d`, `zellij`: `Ctrl+o` -> `d`)하거나 단순히 브라우저/SSH 창을 닫습니다.
2. **이동 도착 후 (기기 B - 자택 또는 다른 머신)**
   - **웹 브라우저 접속 시**: `code-server` 접속 -> 내장 터미널 열기 -> `caw attach` 입력 시 진행 중이던 터미널 화면이 그대로 복원됩니다.
   - **터미널 대화를 IDE 사이드바 패널로 넘겨받으려면**: 터미널의 `agy` 프롬프트에서 `/exit` (또는 `/new`)를 입력해 파일 잠금을 해제한 뒤, IDE 패널 기록 목록에서 해당 대화를 클릭합니다.

---

## 5. `caw` CLI 주요 명령 요약

| 명령 | 동작 설명 |
| --- | --- |
| `caw attach [세션명]` | 활성 멀티플렉서(`tmux` 또는 `zellij`)의 공유 소켓 기준으로 세션 연결/생성 (기본값: `caw`) |
| `caw status` | 실행 중인 `agy` / `claude` / `tmux` / `zellij` 자원 현황 및 활성 대화 `.lock` 점유 조회 |
| `caw unlock` | 브라우저 종료 후 유휴 `agy --hub` 프로세스에 `SIGTERM`을 보내 대화 잠금 즉시 반환 |
| `caw clean [--stop-claude]` | 종료된(`EXITED`) 멀티플렉서 잔여 캐시 세션 정리 (활성 세션은 절대 종료하지 않음) |
| `caw doctor` | 소켓 디렉토리 권한(`0700`), 통합 인증 링크, 활성 멀티플렉서, `systemd Linger=yes` 무결성 진단 |

---

## 6. 보안 및 업스트림 버전 관리 수칙

1. **시크릿 보호**: `.env` 파일은 `chmod 600` 권한이 강제되며, 평문 `CAW_PASSWORD` 대신 Argon2 해시(`CAW_HASHED_PASSWORD`) 사용을 권장합니다. 빈 비밀번호나 예시 비밀번호로는 설치가 거부됩니다(Fail-Close).
2. **네트워크 최소 노출**: `CAW_BIND_ADDR` 기본값은 `127.0.0.1`입니다. 리버스 프록시가 별도 서버에서 동작할 때만 내부망 사설 IP로 변경하고 공인 인터페이스(`0.0.0.0`) 직접 노출은 피하십시오.
3. **이미지 태그 고정**: 예기치 않은 업스트림 변경 방지를 위해 `:latest` 대신 검증된 버전 태그(`CAW_IMAGE_TAG=4.145.2`)를 고정합니다. 버전 업그레이드 시에는 비활성 시간대에 `.env`의 태그만 변경 후 기동하고, 이상 시 즉시 이전 태그로 복구하십시오.
