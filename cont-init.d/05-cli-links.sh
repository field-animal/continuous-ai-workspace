#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 05 - 공용 CLI 래퍼 심볼릭 링크 연결
# 목적:
#   단일 파일 바인드 마운트 대신 읽기 전용 디렉토리(/opt/caw/bin:ro)를 마운트하고
#   심볼릭 링크로 노출하여, 호스트에서 git pull 업데이트 시 컨테이너 재기동 없이 즉시 반영 보장
# 비고: 멀티플렉서 래퍼(zellij, tmux)는 기본 비활성 원칙에 따라 본 모듈에서 연결하지 않음
# =============================================================================
set -euo pipefail

for cli_tool in agy claude caw; do
    if [[ -x "/opt/caw/bin/${cli_tool}" ]]; then
        ln -snf "/opt/caw/bin/${cli_tool}" "/usr/local/bin/${cli_tool}"
    fi
done
