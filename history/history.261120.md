# 변경 이력 - 2026-11-20

## (17:31 KST) - Antigravity

- **[Docs] 컨테이너 환경의 Claude Code OAuth 콜백(`localhost`) 연결 실패 원인 및 조치 방법 `FAQ.md` 추가 (`v0.1.12-261120`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.12-261120` (`./VERSION`)
  - **대상**:
    - `./FAQ.md`
    - `./VERSION`, `./README.md`, `./bin/caw`
    - `./history/history.261120.md` (신규)
  - **내용**:
    1. `./FAQ.md`에 `Q5` 항목을 신설하여 웹 IDE(`code-server`) 컨테이너 네트워크 네임스페이스 분리로 인해 Claude OAuth 로그인 시 브라우저 `localhost:<포트>/callback` 리다이렉트가 연결 거부되는 기술적 원인을 명시.
    2. 컨테이너 네트워크를 유지한 상태에서 `code-server` 내장 터미널 `curl`을 이용한 내부 루프백 콜백 전달 절차(패널 유지 및 큰따옴표 감싸기 주의사항 포함)와 호스트 스탠드얼론 `claude` CLI 볼륨 공유 인증 절차를 정리.

## (17:46 KST) - Antigravity

- **[Docs] Antigravity·Claude 공통 OAuth 콜백 가이드 통합 및 NPM 정규식(`ide-[0-9]+`) 설정법 보완 (`v0.1.13-261120`)**
  - **작업자**: Antigravity
  - **대응 버전**: `0.1.13-261120` (`./VERSION`)
  - **대상**:
    - `./FAQ.md`, `./examples/npm-nginx.conf.example`
    - `./VERSION`, `./README.md`, `./bin/caw`
    - `./history/history.261120.md`
  - **내용**:
    1. `./FAQ.md`의 `Q1`에 리버스 프록시 정규식(`^ide-[0-9]+\.<도메인>$`) 분기 사유 및 Nginx 접두사 와일드카드(`ide-*`) 불가 주의사항을 보강하고, `Q5`를 Claude Code와 Google Antigravity 공통 OAuth `localhost` 콜백 해결 절차로 통합 보완.
    2. `./examples/npm-nginx.conf.example` 상단 NPM 설정 요약에 타 프록시 호스트와의 와일드카드 충돌을 방지하는 `Advanced` 탭 `server_name ~^ide-[0-9]+\.example\.com$;` 단일 행 설정법과 `location /` 미선언 주의사항 명시.
