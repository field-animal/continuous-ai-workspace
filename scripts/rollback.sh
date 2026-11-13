#!/usr/bin/env bash
# =============================================================================
# CAW (Continuous AI Workspace) 원복(롤백) 스크립트 (scripts/rollback.sh)
# 목적:
#   install.sh(--adopt 포함)가 기록한 .caw-state/manifest.env 를 기반으로
#   CAW 컨테이너를 중지·제거하고 기존 백업 컨테이너 및 호스트 CLI 바이너리를 원상 복구함
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${STACK_ROOT}/lib/common.sh"

DRY_RUN=0
ENV_FILE="${STACK_ROOT}/.env"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --env-file)
            ENV_FILE="${2:?파일 경로 필요}"
            shift 2
            ;;
        -h|--help)
            printf '사용법: %s [--dry-run] [--env-file <경로>]\n' "$(basename "$0")"
            exit 0
            ;;
        *)
            caw_err "알 수 없는 옵션입니다: $1"
            exit 1
            ;;
    esac
done

run_or_echo() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        caw_info "[DRY-RUN] 실행 예정: $*"
    else
        "$@"
    fi
}

MANIFEST_FILE="${STACK_ROOT}/.caw-state/manifest.env"
if [[ ! -f "${MANIFEST_FILE}" ]]; then
    caw_err "롤백 매니페스트 파일을 찾을 수 없습니다: ${MANIFEST_FILE}"
    exit 1
fi

caw_load_env_file "${MANIFEST_FILE}"
if [[ -f "${ENV_FILE}" ]]; then
    caw_load_env_file "${ENV_FILE}"
fi

HOST_HOME_DIR="${CAW_STATE_HOST_HOME:-${HOST_HOME:-${HOME}}}"
CONTAINER_NAME="${CAW_STATE_CONTAINER_NAME:-${CAW_CONTAINER_NAME:-code-server}}"
BACKUP_CONTAINER="${CAW_STATE_BACKUP_CONTAINER:-}"

# 활성 대화 잠금 확인 (진행 중인 작업 손실 방지)
if ! caw_check_no_active_locks "${HOST_HOME_DIR}"; then
    caw_err "활성 AI 에이전트 잠금이 감지되어 롤백을 중단합니다. 세션을 먼저 정상 종료하세요."
    exit 1
fi

# 1. CAW 컨테이너 중지 및 제거
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if [[ -f "${ENV_FILE}" ]]; then
        caw_build_compose_args "${STACK_ROOT}"
        run_or_echo docker compose "${CAW_COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}" down
    elif docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
        run_or_echo docker stop "${CONTAINER_NAME}"
        run_or_echo docker rm "${CONTAINER_NAME}"
    fi
fi

# 2. 호스트 로컬 CLI 심볼릭 링크 제거 및 백업 원형 복원
restore_cli_link() {
    local bin_name="$1"
    local backed_up_flag="$2"
    local target_path="${HOST_HOME_DIR}/.local/bin/${bin_name}"
    local wrapper_real
    wrapper_real="$(realpath -m "${STACK_ROOT}/bin/${bin_name}")"

    if [[ -L "${target_path}" ]]; then
        local current_real
        current_real="$(realpath -m "${target_path}" 2>/dev/null || true)"
        if [[ "${current_real}" == "${wrapper_real}" ]]; then
            run_or_echo rm -f "${target_path}"
        fi
    fi

    if [[ "${backed_up_flag}" == "1" && -e "${target_path}.standalone" ]]; then
        run_or_echo mv "${target_path}.standalone" "${target_path}"
        caw_info "기존 ${bin_name} 실행 파일 원복 완료: ${target_path}"
    fi
}

restore_cli_link "agy" "${CAW_STATE_AGY_BACKED_UP:-0}"
restore_cli_link "zellij" "${CAW_STATE_ZELLIJ_BACKED_UP:-0}"
restore_cli_link "tmux" "${CAW_STATE_TMUX_BACKED_UP:-0}"
restore_cli_link "caw" "0"

# 3. 기존 운영 컨테이너(*-caw-backup) 이름 복원 및 재기동
if [[ -n "${BACKUP_CONTAINER}" ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker container inspect "${BACKUP_CONTAINER}" >/dev/null 2>&1; then
        caw_info "백업된 기존 컨테이너('${BACKUP_CONTAINER}')를 '${CONTAINER_NAME}'으로 복원 및 기동합니다."
        run_or_echo docker rename "${BACKUP_CONTAINER}" "${CONTAINER_NAME}"
        run_or_echo docker update --restart=unless-stopped "${CONTAINER_NAME}"
        run_or_echo docker start "${CONTAINER_NAME}"
    else
        caw_warn "매니페스트에 기록된 백업 컨테이너('${BACKUP_CONTAINER}')가 이미 존재하지 않습니다."
    fi
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
    rm -f "${MANIFEST_FILE}"
fi

caw_info "CAW 원복(롤백) 완료 (DRY_RUN=${DRY_RUN})."
