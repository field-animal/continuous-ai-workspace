#!/usr/bin/env bash
# =============================================================================
# CAW (Continuous AI Workspace) - 공통 유틸리티 및 보안 검증 모듈 (lib/common.sh)
# 목적: eval 없는 안전한 .env 파싱, 미선언 사용자 기본값 동적 치환, 경로·시크릿·잠금 검증 제공
# =============================================================================

# 중복 로드 방지 가드
if [[ "${_CAW_COMMON_LOADED:-0}" == "1" ]]; then
    return 0
fi
readonly _CAW_COMMON_LOADED=1

# 공통 로그 출력 함수 (민감 정보는 절대 인자로 전달하지 말 것)
caw_info() {
    printf '[CAW][INFO] %s\n' "$*"
}

caw_warn() {
    printf '[CAW][WARN] %s\n' "$*" >&2
}

caw_err() {
    printf '[CAW][ERROR] %s\n' "$*" >&2
}

# 절대경로 정규화 및 상위 경계 이탈(../ 등) 검증 함수
# 인자: $1=검증할 경로, $2=허용할 루트 경계(선택, 지정 시 끝 슬래시 포함 비교)
caw_validate_path() {
    local raw_path="${1:-}"
    local allowed_root="${2:-}"

    if [[ -z "${raw_path}" ]]; then
        caw_err "경로 값이 비어 있습니다."
        return 1
    fi

    if [[ "${raw_path}" != /* ]]; then
        caw_err "상대경로는 허용되지 않습니다 (절대경로 필수): ${raw_path}"
        return 1
    fi

    local resolved
    resolved="$(realpath -m -- "${raw_path}")"

    if [[ "${resolved}" == "/" ]]; then
        caw_err "루트(/) 디렉토리 자체는 마운트 대상으로 지정할 수 없습니다."
        return 1
    fi

    if [[ -n "${allowed_root}" ]]; then
        local resolved_root
        resolved_root="$(realpath -m -- "${allowed_root}")"
        if [[ "${resolved}" != "${resolved_root}" && "${resolved}" != "${resolved_root}/"* ]]; then
            caw_err "허용된 디렉토리 경계(${resolved_root}/)를 벗어난 경로입니다: ${resolved}"
            return 1
        fi
    fi

    printf '%s\n' "${resolved}"
}

# eval 및 source 없이 .env 파일을 안전하게 파싱하여 환경변수로 적재하는 함수
# 셸 명령어 주입(Command Injection) 방지를 위해 허용된 키 형식만 추출함
caw_load_env_file() {
    local env_file="${1:-}"
    if [[ ! -f "${env_file}" ]]; then
        caw_err "환경변수 파일을 찾을 수 없습니다: ${env_file}"
        return 1
    fi

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "${line}" || "${line}" == \#* ]]; then
            continue
        fi

        if [[ "${line}" != *=* ]]; then
            caw_err ".env 문법 오류 (KEY=VALUE 형식이 아님): ${line%%=*}"
            return 1
        fi

        key="${line%%=*}"
        value="${line#*=}"

        # 엄격한 변수명 화이트리스트 패턴 검증
        if [[ ! "${key}" =~ ^(PUID|PGID|TZ|HOST_USER|HOST_HOME|CAW_[A-Z0-9_]+)$ ]]; then
            caw_err "허용되지 않은 환경변수 키가 포함되어 있습니다: ${key}"
            return 1
        fi

        # 양끝 따옴표 제거 (명령 치환 실행 없음)
        if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi

        export "${key}=${value}"
    done < "${env_file}"
}

# .env 에 미선언(빈 값)된 사용자·경로·세션·멀티플렉서 설정을 현재 실행 계정 기준으로 동적 치환하는 함수
caw_resolve_runtime_defaults() {
    PUID="${PUID:-$(id -u)}"
    PGID="${PGID:-$(id -g)}"
    HOST_USER="${HOST_USER:-$(id -un)}"
    HOST_HOME="$(caw_validate_path "${HOST_HOME:-${HOME}}")"
    CAW_CONFIG_DIR="$(caw_validate_path "${CAW_CONFIG_DIR:-${HOST_HOME}/.local/share/caw/code-server-config}")"
    CAW_WORKSPACE_DIR="$(caw_validate_path "${CAW_WORKSPACE_DIR:-${HOST_HOME}/workspace}")"

    # 하위 호환: 구 CAW_ZELLIJ_SOCKET_DIR 만 정의된 경우 상위 경로로 수용하되 기본은 CAW_MUX_SOCKET_DIR 사용
    local default_mux_dir="${CAW_MUX_SOCKET_DIR:-${HOST_HOME}/.cache/caw/mux}"
    CAW_MUX_SOCKET_DIR="$(caw_validate_path "${default_mux_dir}" "${HOST_HOME}")"

    CAW_MULTIPLEXER="${CAW_MULTIPLEXER:-auto}"
    case "${CAW_MULTIPLEXER}" in
        auto|zellij|tmux|none) ;;
        *)
            caw_err "유효하지 않은 CAW_MULTIPLEXER 값입니다 (auto | zellij | tmux | none 허용): ${CAW_MULTIPLEXER}"
            return 1
            ;;
    esac

    CAW_SHARE_MUX_SOCKET="${CAW_SHARE_MUX_SOCKET:-false}"
    case "${CAW_SHARE_MUX_SOCKET}" in
        true|false) ;;
        *)
            caw_err "유효하지 않은 CAW_SHARE_MUX_SOCKET 값입니다 (true | false 허용): ${CAW_SHARE_MUX_SOCKET}"
            return 1
            ;;
    esac

    CAW_SESSION_NAME="${CAW_SESSION_NAME:-caw}"
    CAW_CONTAINER_NAME="${CAW_CONTAINER_NAME:-code-server}"

    export PUID PGID HOST_USER HOST_HOME CAW_CONFIG_DIR CAW_WORKSPACE_DIR \
           CAW_MUX_SOCKET_DIR CAW_MULTIPLEXER CAW_SHARE_MUX_SOCKET CAW_SESSION_NAME CAW_CONTAINER_NAME
}

# 인증 시크릿 유효성 검증 (기본 예시값이나 빈 비밀번호 기동 원천 차단 - Fail Close)
caw_verify_secrets() {
    local pw="${CAW_PASSWORD:-}"
    local hpw="${CAW_HASHED_PASSWORD:-}"

    if [[ -z "${pw}" && -z "${hpw}" ]]; then
        caw_err "인증 정보가 비어 있습니다. .env 에 CAW_HASHED_PASSWORD 또는 CAW_PASSWORD 를 설정하세요."
        return 1
    fi

    if [[ -z "${hpw}" ]]; then
        if [[ "${pw}" == "change_me"* || "${pw}" == "password" || "${#pw}" -lt 8 ]]; then
            caw_err "안전하지 않은 CAW_PASSWORD 입니다. 최소 8자(권장 12자) 이상의 고유 비밀번호를 설정하세요."
            return 1
        fi
    fi
}

# 활성 에이전트 대화 잠금(.lock) 점유 여부 확인 함수
caw_check_no_active_locks() {
    local host_home="${1:-${HOME}}"
    local lock_found=0
    local lock_dir

    if ! command -v lsof >/dev/null 2>&1; then
        caw_warn "lsof 명령어가 없어 파일 잠금 정밀 검사를 건너뛰고 프로세스 검사로 대체합니다."
        return 0
    fi

    for lock_dir in "${host_home}/.gemini/antigravity/presence" "${host_home}/.gemini/antigravity-cli/presence"; do
        if [[ -d "${lock_dir}" ]]; then
            local active_locks
            active_locks="$(lsof +D "${lock_dir}" 2>/dev/null || true)"
            if [[ -n "${active_locks}" ]]; then
                caw_err "활성 에이전트 잠금이 감지되었습니다 (${lock_dir}):"
                printf '%s\n' "${active_locks}" >&2
                lock_found=1
            fi
        fi
    done

    if [[ "${lock_found}" -ne 0 ]]; then
        return 1
    fi
    return 0
}

# 활성화된 옵션 및 로컬 오버라이드 파일 유무에 따라 docker compose 인자 배열을 조립하는 함수
caw_build_compose_args() {
    local stack_root="${1:?패키지 루트 경로 필요}"
    CAW_COMPOSE_ARGS=(-f "${stack_root}/docker-compose.yml")

    if [[ -f "${stack_root}/compose.override.yml" ]]; then
        CAW_COMPOSE_ARGS+=(-f "${stack_root}/compose.override.yml")
    elif [[ -f "${stack_root}/docker-compose.override.yml" ]]; then
        CAW_COMPOSE_ARGS+=(-f "${stack_root}/docker-compose.override.yml")
    fi

    if [[ "${CAW_ENABLE_DOOD:-false}" == "true" ]]; then
        CAW_COMPOSE_ARGS+=(-f "${stack_root}/compose.dood.yml")
    fi
}
