#!/usr/bin/env bash
# =============================================================================
# CAW (Continuous AI Workspace) 설치 및 기존 서버 전환 스크립트 (scripts/install.sh)
# 지원 옵션:
#   --dry-run              파일/컨테이너 변경 없이 환경변수·경로·잠금·구성을 사전 검증
#   --adopt                기존 운영 중인 동일 이름 컨테이너를 백업 보존 후 무손실 전환
#   --migrate-cli-sessions 기존 antigravity-cli 단독 대화(.db, brain)를 통합 저장소로 복사
#   --env-file <경로>       지정한 환경변수 파일 사용 (기본값: 패키지 루트/.env)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${STACK_ROOT}/lib/common.sh"
# shellcheck source=../lib/multiplexer.sh
source "${STACK_ROOT}/lib/multiplexer.sh"
# shellcheck source=../lib/backup.sh
source "${STACK_ROOT}/lib/backup.sh"

DRY_RUN=0
ADOPT_MODE=0
MIGRATE_SESSIONS=0
ENV_FILE="${STACK_ROOT}/.env"

usage() {
    cat <<EOF
사용법: $(basename "$0") [옵션]

옵션:
  --dry-run                실제 변경 없이 설정·경로·시크릿·대화 잠금 검증만 수행
  --adopt                  기존 운영 서버의 동일 이름 컨테이너를 백업(*-caw-backup) 후 전환
  --migrate-cli-sessions   기존 antigravity-cli 대화 내역을 통합 저장소(antigravity)로 복사
  --env-file <절대경로>     사용할 .env 파일 경로 지정 (기본값: ${STACK_ROOT}/.env)
  -h, --help               도움말 출력
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --adopt)
            ADOPT_MODE=1
            shift
            ;;
        --migrate-cli-sessions)
            MIGRATE_SESSIONS=1
            shift
            ;;
        --env-file)
            ENV_FILE="${2:-}"
            if [[ -z "${ENV_FILE}" ]]; then
                caw_err "--env-file 옵션에는 파일 경로가 필요합니다."
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            caw_err "알 수 없는 옵션입니다: $1"
            usage >&2
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

# 1. 환경변수 파일 권한 보안 강제 및 안전한 파싱 (심볼릭 링크 우회 방어 포함)
if [[ -L "${ENV_FILE}" ]]; then
    caw_err "보안상 심볼릭 링크 형태의 .env 파일은 허용되지 않습니다: ${ENV_FILE}"
    exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
    caw_err "환경변수 파일이 없습니다: ${ENV_FILE}"
    caw_info "먼저 'cp .env.example .env && chmod 600 .env' 실행 후 값을 설정하세요."
    exit 1
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
    chmod 600 "${ENV_FILE}"
fi

caw_load_env_file "${ENV_FILE}"
caw_verify_secrets

# 2. 미선언 항목 실행 사용자 기준 자동 치환 및 경로 경계 검증
caw_resolve_runtime_defaults
caw_info "런타임 매핑 기준: USER=${HOST_USER}(${PUID}:${PGID}), HOME=${HOST_HOME}, WORKSPACE=${CAW_WORKSPACE_DIR}"

# 3. 활성 에이전트 대화 잠금(.lock) 점검 (작업 중 강제 재기동 원천 차단)
if ! caw_check_no_active_locks "${HOST_HOME}"; then
    caw_err "현재 실행 중인 AI 에이전트 대화가 감지되어 설치/전환을 중단합니다."
    caw_info "CLI 세션은 '/exit'로 종료하고, 유휴 IDE 잠금은 종료 후 재시도하세요."
    exit 1
fi

# 4. 최초 도입 백업 및 롤백 매니페스트 선행 기록 준비 (변경 작업 도중 중단되어도 즉시 복구 보장)
STATE_DIR="${STACK_ROOT}/.caw-state"
HOST_BIN_CACHE="${STATE_DIR}/host-bin"
MANIFEST_FILE="${STATE_DIR}/manifest.env"

AGY_BACKED_UP=0
CAW_BACKED_UP=0
ZELLIJ_BACKED_UP=0
TMUX_BACKED_UP=0
BACKUP_CONTAINER=""
CAW_RESOLVED_MUX="none"

if [[ -f "${MANIFEST_FILE}" ]]; then
    # 재실행 시 최초 도입 시점의 백업 메타데이터 유실 방지
    caw_load_env_file "${MANIFEST_FILE}" 1 || true
    [[ "${CAW_STATE_AGY_BACKED_UP:-0}" == "1" ]] && AGY_BACKED_UP=1
    [[ "${CAW_STATE_CAW_BACKED_UP:-0}" == "1" ]] && CAW_BACKED_UP=1
    [[ "${CAW_STATE_ZELLIJ_BACKED_UP:-0}" == "1" ]] && ZELLIJ_BACKED_UP=1
    [[ "${CAW_STATE_TMUX_BACKED_UP:-0}" == "1" ]] && TMUX_BACKED_UP=1
    [[ "${CAW_STATE_HAD_IDE_DIR:-0}" == "1" ]] && CAW_HAD_IDE_DIR=1
    [[ "${CAW_STATE_HAD_CLI_DIR:-0}" == "1" ]] && CAW_HAD_CLI_DIR=1
    [[ -n "${CAW_STATE_BACKUP_CONTAINER:-}" ]] && BACKUP_CONTAINER="${CAW_STATE_BACKUP_CONTAINER}"
fi

save_manifest() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi
    mkdir -p "${STATE_DIR}"
    cat > "${MANIFEST_FILE}.tmp" <<EOF
CAW_STATE_UPDATED_AT="$(date +%Y-%m-%dT%H:%M:%S%z)"
CAW_STATE_HOST_HOME="${HOST_HOME}"
CAW_STATE_CONTAINER_NAME="${CAW_CONTAINER_NAME}"
CAW_STATE_BACKUP_CONTAINER="${BACKUP_CONTAINER}"
CAW_STATE_ACTIVE_MUX="${CAW_RESOLVED_MUX}"
CAW_STATE_HAD_IDE_DIR="${CAW_HAD_IDE_DIR}"
CAW_STATE_HAD_CLI_DIR="${CAW_HAD_CLI_DIR}"
CAW_STATE_AGY_BACKED_UP="${AGY_BACKED_UP}"
CAW_STATE_CAW_BACKED_UP="${CAW_BACKED_UP}"
CAW_STATE_ZELLIJ_BACKED_UP="${ZELLIJ_BACKED_UP}"
CAW_STATE_TMUX_BACKED_UP="${TMUX_BACKED_UP}"
EOF
    chmod 600 "${MANIFEST_FILE}.tmp"
    mv -f "${MANIFEST_FILE}.tmp" "${MANIFEST_FILE}"
}

# 디렉토리 생성·링크 변경 전에 최초 에이전트 DB·세션 원본 백업 및 매니페스트 선행 기록 수행
caw_backup_initial_agent_dirs "${STATE_DIR}" "${HOST_HOME}" "${DRY_RUN}"
save_manifest

# 5. 정책 A 기반 단일 멀티플렉서(zellij | tmux | none) 확정 및 선택 설치
caw_select_and_prepare_mux "${STACK_ROOT}" "${HOST_HOME}" "${CAW_MULTIPLEXER}" "${DRY_RUN}"
caw_info "확정된 단일 멀티플렉서 모드: ${CAW_RESOLVED_MUX}"
save_manifest

# 6. Docker Compose 인자 조립 (compose.override.yml 및 compose.dood.yml 자동 반영)
caw_build_compose_args "${STACK_ROOT}"
caw_info "적용 대상 Compose 구성: ${CAW_COMPOSE_ARGS[*]}"

# 7. 호스트 영속 디렉토리 및 소켓 디렉토리 사전 생성
REQUIRED_DIRS=(
    "${CAW_CONFIG_DIR}"
    "${CAW_WORKSPACE_DIR}"
    "${HOST_HOME}/.claude"
    "${HOST_HOME}/.gemini/antigravity"
    "${HOST_HOME}/.gemini/antigravity-cli"
    "${HOST_HOME}/.local/bin"
    "${HOST_BIN_CACHE}"
)

if [[ "${CAW_SHARE_MUX_SOCKET}" == "true" ]]; then
    REQUIRED_DIRS+=(
        "${CAW_MUX_SOCKET_DIR}"
        "${HOST_HOME}/.cache/zellij"
        "${HOST_HOME}/.config/zellij"
        "${HOST_HOME}/.config/tmux"
    )
fi

for dir in "${REQUIRED_DIRS[@]}"; do
    run_or_echo mkdir -p "${dir}"
done

if [[ "${CAW_SHARE_MUX_SOCKET}" == "true" ]]; then
    run_or_echo chmod 700 "${CAW_MUX_SOCKET_DIR}"
    if [[ "${CAW_RESOLVED_MUX}" == "zellij" ]]; then
        run_or_echo mkdir -p "${CAW_MUX_SOCKET_DIR}/zellij"
        run_or_echo chmod 700 "${CAW_MUX_SOCKET_DIR}/zellij"
    elif [[ "${CAW_RESOLVED_MUX}" == "tmux" ]]; then
        run_or_echo mkdir -p "${CAW_MUX_SOCKET_DIR}/tmux"
        run_or_echo chmod 700 "${CAW_MUX_SOCKET_DIR}/tmux"
        if [[ -f "${HOST_HOME}/.tmux.conf" && ! -e "${HOST_HOME}/.config/tmux/tmux.conf" ]]; then
            run_or_echo ln -s "../../.tmux.conf" "${HOST_HOME}/.config/tmux/tmux.conf"
        fi
    fi
fi

if [[ ! -e "${HOST_HOME}/.gitconfig" ]]; then
    run_or_echo touch "${HOST_HOME}/.gitconfig"
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
    printf '%s\n' "${CAW_RESOLVED_MUX}" > "${HOST_BIN_CACHE}/active-mux"
fi

# 8. Antigravity 인증·설정 심볼릭 링크 연결 및 선택적 세션 마이그레이션
for shared_file in "antigravity-oauth-token" "settings.json"; do
    src_file="${HOST_HOME}/.gemini/antigravity-cli/${shared_file}"
    dst_file="${HOST_HOME}/.gemini/antigravity/${shared_file}"
    if [[ -f "${src_file}" && ! -e "${dst_file}" && ! -L "${dst_file}" ]]; then
        run_or_echo ln -s "../antigravity-cli/${shared_file}" "${dst_file}"
        caw_info "인증/설정 심볼릭 링크 연결: ${dst_file}"
    fi
done

if [[ "${MIGRATE_SESSIONS}" -eq 1 ]]; then
    for sub in "conversations" "brain"; do
        src_sub="${HOST_HOME}/.gemini/antigravity-cli/${sub}"
        dst_sub="${HOST_HOME}/.gemini/antigravity/${sub}"
        if [[ -d "${src_sub}" ]]; then
            run_or_echo mkdir -p "${dst_sub}"
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                caw_info "[DRY-RUN] 기존 ${sub} 데이터 비파괴 복사 예정: ${src_sub} -> ${dst_sub}"
            else
                cp -rn "${src_sub}/." "${dst_sub}/"
                caw_info "기존 ${sub} 데이터 비파괴 복사 완료: ${dst_sub}"
            fi
        fi
    done
fi

# 9. 호스트 CLI 래퍼 배치 (기존 바이너리 백업 즉시 매니페스트 반영)
LAST_LINK_BACKED_UP=0

link_wrapper_with_backup() {
    local bin_name="$1"
    local target_path="${HOST_HOME}/.local/bin/${bin_name}"
    local wrapper_real
    wrapper_real="$(realpath "${STACK_ROOT}/bin/${bin_name}")"
    LAST_LINK_BACKED_UP=0

    if [[ -e "${target_path}" || -L "${target_path}" ]]; then
        local current_real
        current_real="$(realpath -m "${target_path}" 2>/dev/null || true)"
        if [[ "${current_real}" != "${wrapper_real}" && ! -e "${target_path}.standalone" ]]; then
            run_or_echo mv "${target_path}" "${target_path}.standalone"
            LAST_LINK_BACKED_UP=1
            caw_info "기존 ${bin_name} 실행 파일 백업 완료: ${target_path}.standalone"
        fi
    fi
    run_or_echo ln -snf "${STACK_ROOT}/bin/${bin_name}" "${target_path}"
}

unlink_wrapper_if_ours() {
    local bin_name="$1"
    local target_path="${HOST_HOME}/.local/bin/${bin_name}"
    local wrapper_real
    wrapper_real="$(realpath -m "${STACK_ROOT}/bin/${bin_name}")"

    if [[ -L "${target_path}" ]]; then
        local current_real
        current_real="$(realpath -m "${target_path}" 2>/dev/null || true)"
        if [[ "${current_real}" == "${wrapper_real}" ]]; then
            run_or_echo rm -f "${target_path}"
            if [[ -e "${target_path}.standalone" ]]; then
                run_or_echo mv "${target_path}.standalone" "${target_path}"
            fi
        fi
    fi
}

link_wrapper_with_backup "agy"
[[ "${LAST_LINK_BACKED_UP}" == "1" ]] && AGY_BACKED_UP=1
link_wrapper_with_backup "caw"
[[ "${LAST_LINK_BACKED_UP}" == "1" ]] && CAW_BACKED_UP=1

if [[ "${CAW_SHARE_MUX_SOCKET}" == "true" ]]; then
    case "${CAW_RESOLVED_MUX}" in
        zellij)
            unlink_wrapper_if_ours "tmux"
            REAL_HOST_ZELLIJ="$(caw_find_real_binary "${STACK_ROOT}" "${HOST_HOME}" "zellij" || true)"
            if [[ -n "${REAL_HOST_ZELLIJ}" ]]; then
                run_or_echo cp -pf "${REAL_HOST_ZELLIJ}" "${HOST_BIN_CACHE}/zellij"
            fi
            link_wrapper_with_backup "zellij"
            [[ "${LAST_LINK_BACKED_UP}" == "1" ]] && ZELLIJ_BACKED_UP=1
            ;;
        tmux)
            unlink_wrapper_if_ours "zellij"
            link_wrapper_with_backup "tmux"
            [[ "${LAST_LINK_BACKED_UP}" == "1" ]] && TMUX_BACKED_UP=1
            ;;
        none|*)
            unlink_wrapper_if_ours "zellij"
            unlink_wrapper_if_ours "tmux"
            ;;
    esac
else
    unlink_wrapper_if_ours "zellij"
    unlink_wrapper_if_ours "tmux"
    caw_info "호스트 SSH 2중 인증 경계 모드 활성화 - 호스트 순정 멀티플렉서(${CAW_RESOLVED_MUX}) 사용"
fi
save_manifest

if ! caw_find_real_binary "${STACK_ROOT}" "${HOST_HOME}" "claude" >/dev/null 2>&1; then
    caw_warn "호스트 스탠드얼론 claude CLI(${HOST_HOME}/.local/bin/claude)가 감지되지 않았습니다."
fi

# 10. 호스트 systemd Linger 점검 (멀티플렉서 활성 모드일 때만 수행)
if [[ "${CAW_RESOLVED_MUX}" != "none" ]] && command -v loginctl >/dev/null 2>&1; then
    LINGER_VAL="$(loginctl show-user "${HOST_USER}" -p Linger --value 2>/dev/null || echo 'no')"
    if [[ "${LINGER_VAL}" != "yes" ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            caw_info "[DRY-RUN] Linger 비활성 감지 - 'sudo loginctl enable-linger ${HOST_USER}' 실행 예정"
        elif [[ -t 0 ]]; then
            caw_info "SSH 로그아웃 후에도 멀티플렉서 세션을 유지하기 위해 systemd Linger 활성화를 요청합니다."
            sudo loginctl enable-linger "${HOST_USER}"
        else
            caw_warn "비대화형 터미널이므로 sudo를 생략합니다. 수동으로 'sudo loginctl enable-linger ${HOST_USER}'를 실행하세요."
        fi
    fi
fi

# 11. 기존 동일 이름 컨테이너 충돌 검사, Compose 사전 검증 및 --adopt 백업 전환 처리
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    # 기존 컨테이너를 내리기 전에 Compose 문법·치환 검증을 먼저 통과시켜 중단 위험 최소화
    docker compose "${CAW_COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}" config -q
    caw_info "Docker Compose 구성 검증 통과 완료."

    if docker container inspect "${CAW_CONTAINER_NAME}" >/dev/null 2>&1; then
        EXISTING_WORKDIR="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "${CAW_CONTAINER_NAME}" 2>/dev/null || true)"
        if [[ "${EXISTING_WORKDIR}" != "${STACK_ROOT}" ]]; then
            if [[ "${ADOPT_MODE}" -ne 1 ]]; then
                caw_err "타 경로(${EXISTING_WORKDIR:-수동실행})에서 구동 중인 '${CAW_CONTAINER_NAME}' 컨테이너가 이미 존재합니다."
                caw_info "기존 컨테이너를 보존 백업하고 전환하려면 '--adopt' 옵션을 추가해 실행하세요."
                exit 1
            fi

            BACKUP_CONTAINER="${CAW_CONTAINER_NAME}-caw-backup"
            if docker container inspect "${BACKUP_CONTAINER}" >/dev/null 2>&1; then
                caw_err "백업 대상 컨테이너 이름('${BACKUP_CONTAINER}')이 이미 존재합니다. 상태를 먼저 확인하세요."
                exit 1
            fi

            caw_info "기존 컨테이너('${CAW_CONTAINER_NAME}')를 중지하고 백업 이름('${BACKUP_CONTAINER}')으로 보존합니다."
            run_or_echo docker update --restart=no "${CAW_CONTAINER_NAME}"
            run_or_echo docker stop "${CAW_CONTAINER_NAME}"
            run_or_echo docker rename "${CAW_CONTAINER_NAME}" "${BACKUP_CONTAINER}"
            save_manifest
        fi
    fi

    run_or_echo docker compose "${CAW_COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}" up -d
else
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        caw_warn "[DRY-RUN] 현재 셸에서 Docker 데몬 소켓에 접근할 수 없어 컨테이너 검사를 건너뛰었습니다 (정적 검증 완료)."
    else
        caw_err "Docker 데몬에 연결할 수 없습니다. Docker 서비스 및 계정 권한을 확인하세요."
        exit 1
    fi
fi

caw_info "CAW 작업 완료 (DRY_RUN=${DRY_RUN}, MUX=${CAW_RESOLVED_MUX}). 'caw doctor' 및 'caw status'로 환경을 확인하세요."
