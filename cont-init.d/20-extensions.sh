#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 20 - AI 확장 프로그램 자동 설치 (공식 갤러리 전용)
# 목적: 최초 기동 시 google.google-antigravity 및 anthropic.claude-code 미설치 여부를
#       점검하여 code-server 기본 공식 갤러리(Open VSX)에서 자동 설치함
# 비고: 비공식 마켓플레이스 우회 설정 없이 공식 채널만 사용하며 CAW_AUTO_INSTALL_EXTENSIONS=false 시 생략됨
# =============================================================================
set -euo pipefail

if [[ "${CAW_AUTO_INSTALL_EXTENSIONS:-true}" != "true" ]]; then
    echo "[caw-init:20-extensions] 확장 자동 설치 비활성화 상태 - 건너뜁니다."
    exit 0
fi

CODE_SERVER_BIN="/app/code-server/bin/code-server"
EXT_DIR="/config/extensions"
TARGET_USER="abc"

if [[ ! -x "${CODE_SERVER_BIN}" ]]; then
    echo "[caw-init:20-extensions] code-server 실행 파일을 찾을 수 없어 건너뜁니다: ${CODE_SERVER_BIN}"
    exit 0
fi

mkdir -p "${EXT_DIR}"
chown "${TARGET_USER}:${TARGET_USER}" "${EXT_DIR}"

# 고정 허용 목록(Allow-list)에 등록된 확장만 점검 및 설치
REQUIRED_EXTENSIONS=(
    "google.google-antigravity"
    "anthropic.claude-code"
)

for ext_id in "${REQUIRED_EXTENSIONS[@]}"; do
    # 이미 설치된 버전 폴더가 존재하면 재다운로드 생략 (기동 속도 보장 및 기존 버전 보존)
    if compgen -G "${EXT_DIR}/${ext_id}-*" >/dev/null; then
        echo "[caw-init:20-extensions] 설치 확인됨: ${ext_id}"
        continue
    fi

    echo "[caw-init:20-extensions] 공식 갤러리에서 확장 설치 시작: ${ext_id}"
    s6-setuidgid "${TARGET_USER}" "${CODE_SERVER_BIN}" \
        --user-data-dir /config/data \
        --extensions-dir "${EXT_DIR}" \
        --install-extension "${ext_id}"
done
