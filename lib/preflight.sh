#!/usr/bin/env bash
# =============================================================================
# CAW 기존 컨테이너 호환성 및 포트 충돌 사전 검증 모듈 (lib/preflight.sh)
# 목적:
#   1) 목표 포트(기본 8443)를 다른 이름의 컨테이너가 이미 점유 중인지 기동 전 사전 차단
#   2) --adopt 전환 시 기존 컨테이너의 /config 경로 불일치 경고 및 내부 .gemini 데이터
#      덮어쓰기(마운트 마스킹) 위험을 기동 전에 감지하여 세션 가려짐 오동작 원천 차단
# =============================================================================

if [[ "${_CAW_PREFLIGHT_LIB_LOADED:-0}" == "1" ]]; then
    return 0
fi
readonly _CAW_PREFLIGHT_LIB_LOADED=1

# 타 컨테이너의 동일 호스트 포트 점유 여부 사전 점검 함수
caw_check_port_conflict() {
    local target_container="$1"
    local bind_addr="$2"
    local target_port="$3"

    local cname cports
    while IFS=$'\t' read -r cname cports; do
        [[ -z "${cname}" || "${cname}" == "${target_container}" ]] && continue
        # 0.0.0.0:<port>->, [::]:<port>->, 또는 동일 바인드 IP:<port>-> 매칭 검사
        if [[ "${cports}" == *"0.0.0.0:${target_port}->"* ]] || \
           [[ "${cports}" == *":::${target_port}->"* ]] || \
           [[ "${cports}" == *"[::]:${target_port}->"* ]] || \
           [[ "${cports}" == *"${bind_addr}:${target_port}->"* ]]; then
            caw_err "타 컨테이너('${cname}')가 호스트 포트 ${target_port}를 이미 점유 중입니다: ${cports}"
            caw_info ".env 의 CAW_PORT 를 변경하거나 기존 컨테이너 이름을 CAW_CONTAINER_NAME 에 일치시키세요."
            return 1
        fi
    done < <(docker ps --format '{{.Names}}	{{.Ports}}' 2>/dev/null || true)

    return 0
}

# --adopt 전환 시 기존 컨테이너의 마운트 구조와 CAW 설정 간 정합성 사전 점검 함수
caw_inspect_adopt_compatibility() {
    local container_name="$1"
    local caw_config_dir="$2"
    local host_home="$3"

    local existing_cfg_src=""
    local has_separate_gemini_mount=""

    existing_cfg_src="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' "${container_name}" 2>/dev/null || true)"
    has_separate_gemini_mount="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config/.gemini"}}1{{end}}{{end}}' "${container_name}" 2>/dev/null || true)"

    if [[ -z "${existing_cfg_src}" ]]; then
        return 0
    fi

    local resolved_existing_cfg
    resolved_existing_cfg="$(realpath -m -- "${existing_cfg_src}" 2>/dev/null || printf '%s' "${existing_cfg_src}")"

    # 1) /config 경로 불일치 안내 경고 (의도적 신규 경로 분리일 수 있으므로 경고 출력)
    if [[ "${resolved_existing_cfg}" != "${caw_config_dir}" ]]; then
        caw_warn "기존 컨테이너의 /config 경로(${resolved_existing_cfg})와 .env 의 CAW_CONFIG_DIR(${caw_config_dir})이 다릅니다."
        caw_warn "기존 확장·설정을 그대로 승계하려면 .env 에 CAW_CONFIG_DIR=${resolved_existing_cfg} 를 지정하세요."
    fi

    # 2) 기존 컨테이너가 .gemini 를 호스트 홈에 분리 마운트하지 않고 /config 내부에만 보관해 온 경우 가려짐 차단
    if [[ -z "${has_separate_gemini_mount}" && -d "${resolved_existing_cfg}/.gemini" ]]; then
        local resolved_inner_gemini resolved_host_gemini
        resolved_inner_gemini="$(realpath -m -- "${resolved_existing_cfg}/.gemini" 2>/dev/null || true)"
        resolved_host_gemini="$(realpath -m -- "${host_home}/.gemini" 2>/dev/null || true)"

        if [[ "${resolved_inner_gemini}" != "${resolved_host_gemini}" ]] && \
           [[ -n "$(ls -A "${resolved_existing_cfg}/.gemini" 2>/dev/null || true)" ]]; then
            caw_err "기존 컨테이너 내부 경로(${resolved_existing_cfg}/.gemini)에 분리되지 않은 에이전트 데이터가 존재합니다."
            caw_info "그대로 전환하면 ${host_home}/.gemini 마운트에 가려져 기존 대화가 보이지 않게 됩니다."
            caw_info "먼저 기존 데이터를 '${host_home}/.gemini'로 복사·통합한 뒤 다시 실행하세요."
            return 1
        fi
    fi

    return 0
}
