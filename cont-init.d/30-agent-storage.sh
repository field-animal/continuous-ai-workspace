#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 30 - AI 에이전트 통합 저장소 정합성 보장
# 목적: Antigravity IDE(antigravity/)와 CLI(antigravity-cli/) 간 인증·설정 심볼릭 링크를 멱등 연결
# =============================================================================
set -euo pipefail

TARGET_USER="abc"
GEMINI_ROOT="/config/.gemini"
IDE_DIR="${GEMINI_ROOT}/antigravity"
CLI_DIR="${GEMINI_ROOT}/antigravity-cli"

mkdir -p "${IDE_DIR}" "${CLI_DIR}"
chown "${TARGET_USER}:${TARGET_USER}" "${IDE_DIR}" "${CLI_DIR}"

for shared_file in "antigravity-oauth-token" "settings.json"; do
    src_path="${CLI_DIR}/${shared_file}"
    dst_path="${IDE_DIR}/${shared_file}"

    if [[ -f "${src_path}" && ! -e "${dst_path}" && ! -L "${dst_path}" ]]; then
        s6-setuidgid "${TARGET_USER}" ln -s "../antigravity-cli/${shared_file}" "${dst_path}"
        echo "[caw-init:30-agent-storage] 심볼릭 링크 연결 완료: ${dst_path} -> ../antigravity-cli/${shared_file}"
    fi
done
