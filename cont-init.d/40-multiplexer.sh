#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 40 - 선택된 단일 멀티플렉서(zellij | tmux | none) 초기화
# 목적:
#   1) 공유 소켓 상위 디렉토리 및 활성 멀티플렉서 소켓 디렉토리 권한(0700) 보장
#   2) 선택된 단 1종의 멀티플렉서 래퍼만 /usr/local/bin 에 노출하여 중복 실행 및 충돌 방지
#   3) tmux 선택 시에만 컨테이너 내 tmux 클라이언트를 멱등 설치
# =============================================================================
set -euo pipefail

TARGET_USER="abc"
MUX_ROOT="${CAW_MUX_SOCKET_DIR:-/config/.cache/caw/mux}"
ACTIVE_MUX_FILE="/opt/caw/host-bin/active-mux"

# install.sh 가 기록한 확정 모드 우선 참조, 없으면 환경변수 CAW_MULTIPLEXER 참조
ACTIVE_MUX="${CAW_MULTIPLEXER:-auto}"
if [[ -f "${ACTIVE_MUX_FILE}" ]]; then
    ACTIVE_MUX="$(tr -d '[:space:]' < "${ACTIVE_MUX_FILE}")"
fi

if [[ "${ACTIVE_MUX}" == "auto" ]]; then
    if [[ -x "/opt/caw/host-bin/zellij" ]]; then
        ACTIVE_MUX="zellij"
    elif command -v tmux >/dev/null 2>&1; then
        ACTIVE_MUX="tmux"
    else
        ACTIVE_MUX="none"
    fi
fi

mkdir -p "${MUX_ROOT}"
chmod 700 "${MUX_ROOT}"
chown "${TARGET_USER}:${TARGET_USER}" "${MUX_ROOT}"

case "${ACTIVE_MUX}" in
    zellij)
        Z_DIR="${ZELLIJ_SOCKET_DIR:-${MUX_ROOT}/zellij}"
        mkdir -p "${Z_DIR}"
        chmod 700 "${Z_DIR}"
        chown "${TARGET_USER}:${TARGET_USER}" "${Z_DIR}"

        # 비선택 멀티플렉서 래퍼 제거 후 zellij 래퍼만 연결
        rm -f /usr/local/bin/tmux
        ln -snf /opt/caw/bin/zellij /usr/local/bin/zellij
        echo "[caw-init:40-multiplexer] zellij 단독 소켓 연동 활성화 (${Z_DIR})"
        ;;
    tmux)
        T_DIR="${TMUX_TMPDIR:-${MUX_ROOT}/tmux}"
        mkdir -p "${T_DIR}"
        chmod 700 "${T_DIR}"
        chown "${TARGET_USER}:${TARGET_USER}" "${T_DIR}"

        # 컨테이너 내부에 네이티브 tmux 클라이언트가 없을 경우에만 1회 멱등 설치
        if [[ ! -x "/usr/bin/tmux" ]]; then
            echo "[caw-init:40-multiplexer] 컨테이너 내 tmux 클라이언트 설치 진행..."
            export DEBIAN_FRONTEND=noninteractive
            if apt-get update && apt-get install -y --no-install-recommends tmux; then
                rm -rf /var/lib/apt/lists/*
            else
                echo "[caw-init:40-multiplexer] 경고: 네트워크 제한으로 컨테이너 내 tmux 설치 실패" >&2
            fi
        fi

        rm -f /usr/local/bin/zellij
        ln -snf /opt/caw/bin/tmux /usr/local/bin/tmux
        echo "[caw-init:40-multiplexer] tmux 단독 소켓 연동 활성화 (${T_DIR})"
        ;;
    none|*)
        rm -f /usr/local/bin/zellij /usr/local/bin/tmux
        echo "[caw-init:40-multiplexer] 멀티플렉서 비활성(none) 모드 유지"
        ;;
esac
