#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 30 - AI 세션 저장소 및 멀티플렉서 소켓 디렉토리 정합성 보장
# 목적:
#   1) Antigravity IDE(antigravity/)와 CLI(antigravity-cli/) 간 인증·설정 심볼릭 링크를 멱등 연결
#   2) 호스트-컨테이너 공유 Zellij 소켓 디렉토리 권한(0700) 및 소유권 보장
# =============================================================================
set -euo pipefail

TARGET_USER="abc"
GEMINI_ROOT="/config/.gemini"
IDE_DIR="${GEMINI_ROOT}/antigravity"
CLI_DIR="${GEMINI_ROOT}/antigravity-cli"
SOCKET_DIR="${ZELLIJ_SOCKET_DIR:-/config/.cache/zellij/ipc}"

# 1. 공유 디렉토리 생성 및 최소 권한(소유자 전용 0700) 설정
mkdir -p "${IDE_DIR}" "${CLI_DIR}" "${SOCKET_DIR}"
chmod 700 "${SOCKET_DIR}"
chown "${TARGET_USER}:${TARGET_USER}" "${IDE_DIR}" "${CLI_DIR}" "${SOCKET_DIR}"

# 2. CLI에서 이미 로그인해 둔 토큰 및 설정 파일이 있을 경우 IDE 통합 디렉토리로 안전 연결
for shared_file in "antigravity-oauth-token" "settings.json"; do
    src_path="${CLI_DIR}/${shared_file}"
    dst_path="${IDE_DIR}/${shared_file}"

    if [[ -f "${src_path}" && ! -e "${dst_path}" && ! -L "${dst_path}" ]]; then
        s6-setuidgid "${TARGET_USER}" ln -s "../antigravity-cli/${shared_file}" "${dst_path}"
        echo "[caw-init:30-agent-storage] 심볼릭 링크 연결 완료: ${dst_path} -> ../antigravity-cli/${shared_file}"
    fi
done
