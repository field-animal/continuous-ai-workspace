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

# 1. 환경변수 파일 권한 보안 강제 및 안전한 파싱
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

# 4. Docker Compose 인자 조립 (compose.override.yml 및 compose.dood.yml 자동 반영)
caw_build_compose_args "${STACK_ROOT}"
caw_info "적용 대상 Compose 구성: ${CAW_COMPOSE_ARGS[*]}"

# 5. 호스트 영속 디렉토리 및 초기 파일 사전 생성 (Docker 데몬의 root 소유 폴더 자동 생성 방지)
STATE_DIR="${STACK_ROOT}/.caw-state"
HOST_BIN_CACHE="${STATE_DIR}/host-bin"
MANIFEST_FILE="${STATE_DIR}/manifest.env"

REQUIRED_DIRS=(
    "${CAW_CONFIG_DIR}"
    "${CAW_WORKSPACE_DIR}"
    "${HOST_HOME}/.claude"
    "${HOST_HOME}/.gemini/antigravity"
    "${HOST_HOME}/.gemini/antigravity-cli"
    "${HOST_HOME}/.cache/zellij"
    "${CAW_ZELLIJ_SOCKET_DIR}"
    "${HOST_HOME}/.config/zellij"
    "${HOST_HOME}/.local/bin"
    "${HOST_BIN_CACHE}"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    run_or_echo mkdir -p "${dir}"
done
run_or_echo chmod 700 "${CAW_ZELLIJ_SOCKET_DIR}"

if [[ ! -e "${HOST_HOME}/.gitconfig" ]]; then
    run_or_echo touch "${HOST_HOME}/.gitconfig"
fi

# 6. Antigravity 인증·설정 심볼릭 링크 연결 및 선택적 세션 마이그레이션
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

# 7. 호스트 실제 zellij 바이너리 탐색 (컨테이너-호스트 프로토콜 버전 100% 일치용 로컬 캐시)
find_non_wrapper_binary() {
    local bin_name="$1"
    local wrapper_real
    wrapper_real="$(realpath -m "${STACK_ROOT}/bin/${bin_name}")"

    if [[ -x "${HOST_HOME}/.local/bin/${bin_name}.standalone" ]]; then
        realpath "${HOST_HOME}/.local/bin/${bin_name}.standalone"
        return 0
    fi

    local IFS=':'
    local d cand cand_real
    for d in ${PATH} "${HOST_HOME}/.local/bin" "${HOST_HOME}/.cargo/bin" "/usr/local/bin" "/usr/bin"; do
        [[ -z "${d}" ]] && continue
        cand="${d}/${bin_name}"
        if [[ -x "${cand}" ]]; then
            cand_real="$(realpath "${cand}" 2>/dev/null || true)"
            if [[ -n "${cand_real}" && "${cand_real}" != "${wrapper_real}" ]]; then
                printf '%s\n' "${cand_real}"
                return 0
            fi
        fi
    done
    return 1
}

AGY_BACKED_UP=0
ZELLIJ_BACKED_UP=0
SYMLINK_ZELLIJ=0

# agy 래퍼 심볼릭 링크 배치 (기존 스탠드얼론 파일 존재 시 백업 보존)
TARGET_LOCAL_AGY="${HOST_HOME}/.local/bin/agy"
WRAPPER_AGY_REAL="$(realpath "${STACK_ROOT}/bin/agy")"
if [[ -e "${TARGET_LOCAL_AGY}" || -L "${TARGET_LOCAL_AGY}" ]]; then
    CURRENT_AGY_REAL="$(realpath -m "${TARGET_LOCAL_AGY}" 2>/dev/null || true)"
    if [[ "${CURRENT_AGY_REAL}" != "${WRAPPER_AGY_REAL}" && ! -e "${TARGET_LOCAL_AGY}.standalone" ]]; then
        run_or_echo mv "${TARGET_LOCAL_AGY}" "${TARGET_LOCAL_AGY}.standalone"
        AGY_BACKED_UP=1
        caw_info "기존 agy 실행 파일 백업 완료: ${TARGET_LOCAL_AGY}.standalone"
    fi
fi
run_or_echo ln -snf "${STACK_ROOT}/bin/agy" "${TARGET_LOCAL_AGY}"

# caw 통합 CLI 심볼릭 링크 배치
TARGET_LOCAL_CAW="${HOST_HOME}/.local/bin/caw"
run_or_echo ln -snf "${STACK_ROOT}/bin/caw" "${TARGET_LOCAL_CAW}"

# zellij 바이너리 동기화 및 소켓 고정 래퍼 배치 (설치된 경우에만 수행 - 멀티플렉서 중립성 유지)
REAL_HOST_ZELLIJ="$(find_non_wrapper_binary zellij || true)"
if [[ -n "${REAL_HOST_ZELLIJ}" ]]; then
    run_or_echo cp -pf "${REAL_HOST_ZELLIJ}" "${HOST_BIN_CACHE}/zellij"
    TARGET_LOCAL_ZELLIJ="${HOST_HOME}/.local/bin/zellij"
    WRAPPER_ZELLIJ_REAL="$(realpath "${STACK_ROOT}/bin/zellij")"
    if [[ -e "${TARGET_LOCAL_ZELLIJ}" || -L "${TARGET_LOCAL_ZELLIJ}" ]]; then
        CURRENT_ZELLIJ_REAL="$(realpath -m "${TARGET_LOCAL_ZELLIJ}" 2>/dev/null || true)"
        if [[ "${CURRENT_ZELLIJ_REAL}" != "${WRAPPER_ZELLIJ_REAL}" && ! -e "${TARGET_LOCAL_ZELLIJ}.standalone" ]]; then
            run_or_echo mv "${TARGET_LOCAL_ZELLIJ}" "${TARGET_LOCAL_ZELLIJ}.standalone"
            ZELLIJ_BACKED_UP=1
            caw_info "기존 zellij 실행 파일 백업 완료: ${TARGET_LOCAL_ZELLIJ}.standalone"
        fi
    fi
    run_or_echo ln -snf "${STACK_ROOT}/bin/zellij" "${TARGET_LOCAL_ZELLIJ}"
    SYMLINK_ZELLIJ=1
    caw_info "호스트-컨테이너 동일 버전 zellij 동기화 및 소켓 래퍼 연결 완료: ${REAL_HOST_ZELLIJ}"
else
    caw_warn "호스트에서 zellij가 감지되지 않았습니다. zellij 사용 시 설치 후 install.sh를 다시 실행하세요."
fi

# 공식 스탠드얼론 claude CLI 설치 여부 안내 점검
if ! find_non_wrapper_binary claude >/dev/null 2>&1; then
    caw_warn "호스트 스탠드얼론 claude CLI(${HOST_HOME}/.local/bin/claude)가 감지되지 않았습니다."
    caw_info "터미널에서 claude CLI 사용이 필요하면 공식 스탠드얼론 설치 후 사용하세요."
fi

# 8. 호스트 systemd Linger(SSH 로그아웃 후 멀티플렉서 세션 생존 보장) 점검
if command -v loginctl >/dev/null 2>&1; then
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

# 9. 기존 동일 이름 컨테이너 충돌 검사 및 --adopt 백업 전환 처리
BACKUP_CONTAINER=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
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
        fi
    fi

    # 10. 롤백 매니페스트 기록 (기존 상태가 없을 때만 최초 백업 원형을 보존하거나 갱신)
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        if [[ -f "${MANIFEST_FILE}" ]]; then
            caw_load_env_file "${MANIFEST_FILE}" || true
            [[ "${CAW_STATE_AGY_BACKED_UP:-0}" == "1" ]] && AGY_BACKED_UP=1
            [[ "${CAW_STATE_ZELLIJ_BACKED_UP:-0}" == "1" ]] && ZELLIJ_BACKED_UP=1
            [[ -z "${BACKUP_CONTAINER}" && -n "${CAW_STATE_BACKUP_CONTAINER:-}" ]] && BACKUP_CONTAINER="${CAW_STATE_BACKUP_CONTAINER}"
        fi

        cat > "${MANIFEST_FILE}" <<EOF
CAW_STATE_CREATED_AT="$(date +%Y-%m-%dT%H:%M:%S%z)"
CAW_STATE_HOST_HOME="${HOST_HOME}"
CAW_STATE_CONTAINER_NAME="${CAW_CONTAINER_NAME}"
CAW_STATE_BACKUP_CONTAINER="${BACKUP_CONTAINER}"
CAW_STATE_AGY_BACKED_UP="${AGY_BACKED_UP}"
CAW_STATE_ZELLIJ_BACKED_UP="${ZELLIJ_BACKED_UP}"
CAW_STATE_SYMLINK_AGY="1"
CAW_STATE_SYMLINK_CAW="1"
CAW_STATE_SYMLINK_ZELLIJ="${SYMLINK_ZELLIJ}"
EOF
        chmod 600 "${MANIFEST_FILE}"
    fi

    # 11. Compose 구문 검증 및 기동
    docker compose "${CAW_COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}" config -q
    caw_info "Docker Compose 구성 검증 통과 완료."
    run_or_echo docker compose "${CAW_COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}" up -d
else
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        caw_warn "[DRY-RUN] 현재 셸에서 Docker 데몬 소켓에 접근할 수 없어 컨테이너 검사를 건너뛰었습니다 (정적 검증 완료)."
    else
        caw_err "Docker 데몬에 연결할 수 없습니다. Docker 서비스 및 계정 권한을 확인하세요."
        exit 1
    fi
fi

caw_info "CAW 작업 완료 (DRY_RUN=${DRY_RUN}). 'caw doctor' 및 'caw attach'로 환경을 확인하세요."
