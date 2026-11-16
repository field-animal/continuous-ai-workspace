#!/usr/bin/env bash
# =============================================================================
# CAW 최초 도입 백업 및 실패 복구 독립 모듈 (lib/backup.sh)
# 목적:
#   1) 최초 도입 변경 작업 전 에이전트 DB·세션 디렉토리(antigravity, antigravity-cli)의
#      원본 아카이브(pre-caw-gemini.tar.gz, 권한 0600)를 1회 원자적으로 생성·보관
#   2) 도입 실패 또는 롤백 시 보관된 아카이브로 완전 분리된 도입 이전 상태를 복원
# =============================================================================

if [[ "${_CAW_BACKUP_LIB_LOADED:-0}" == "1" ]]; then
    return 0
fi
readonly _CAW_BACKUP_LIB_LOADED=1

CAW_HAD_IDE_DIR=0
CAW_HAD_CLI_DIR=0

# 최초 도입 전 에이전트 세션·DB 디렉토리 원본 보관 함수 (재실행 시 최초 백업본 보존)
caw_backup_initial_agent_dirs() {
    local state_dir="$1"
    local host_home="$2"
    local dry_run="${3:-0}"
    local gemini_root="${host_home}/.gemini"
    local archive_path="${state_dir}/pre-caw-gemini.tar.gz"

    if [[ -f "${archive_path}" ]]; then
        caw_info "최초 도입 백업본이 이미 존재하므로 원본을 유지합니다: ${archive_path}"
        return 0
    fi

    local targets=()
    if [[ -d "${gemini_root}/antigravity" ]]; then
        CAW_HAD_IDE_DIR=1
        targets+=("antigravity")
    fi
    if [[ -d "${gemini_root}/antigravity-cli" ]]; then
        CAW_HAD_CLI_DIR=1
        targets+=("antigravity-cli")
    fi

    if [[ "${#targets[@]}" -eq 0 ]]; then
        caw_info "기존 에이전트 세션 디렉토리가 없는 신규 환경입니다 (빈 상태 기록)."
        return 0
    fi

    if [[ "${dry_run}" == "1" ]]; then
        caw_info "[DRY-RUN] 도입 전 에이전트 DB·세션 디렉토리 백업 예정: ${archive_path} (${targets[*]})"
        return 0
    fi

    mkdir -p "${state_dir}"
    local tmp_archive="${archive_path}.tmp"
    rm -f "${tmp_archive}"

    # 중도 실패 시 불완전 파일 잔류를 막기 위해 임시 파일 생성 후 원자적 이름 변경 수행
    (umask 077 && tar -czf "${tmp_archive}" -C "${gemini_root}" "${targets[@]}")
    chmod 600 "${tmp_archive}"
    mv -f "${tmp_archive}" "${archive_path}"
    caw_info "도입 전 에이전트 DB·세션 원본 백업 완료: ${archive_path}"
}

# 롤백 시 보관된 원본 아카이브로 에이전트 DB·세션 디렉토리를 복원(재분리)하는 함수
caw_restore_initial_agent_dirs() {
    local state_dir="$1"
    local host_home="$2"
    local had_ide="${3:-0}"
    local had_cli="${4:-0}"
    local dry_run="${5:-0}"
    local gemini_root="${host_home}/.gemini"
    local archive_path="${state_dir}/pre-caw-gemini.tar.gz"
    local safety_path="${state_dir}/pre-rollback-safety.tar.gz"

    if [[ "${dry_run}" == "1" ]]; then
        caw_info "[DRY-RUN] 에이전트 DB·세션 디렉토리를 도입 이전 원본 상태로 복원 예정 (${gemini_root})"
        return 0
    fi

    mkdir -p "${gemini_root}"

    # 도입 전 기존 데이터가 있었던 환경에서는 반드시 원본 아카이브의 존재와 무결성(tar -tzf)을 먼저 확인한 뒤에만 교체 수행
    if [[ "${had_ide}" == "1" || "${had_cli}" == "1" ]]; then
        if [[ ! -f "${archive_path}" ]] || ! tar -tzf "${archive_path}" >/dev/null 2>&1; then
            caw_err "원본 백업 아카이브(${archive_path})가 없거나 손상되어 세션 디렉토리 삭제를 차단했습니다."
            caw_info "현재 세션 데이터를 그대로 유지하려면 '--keep-sessions' 옵션으로 롤백하세요."
            return 1
        fi
    fi

    # 롤백 직전 상태도 만일의 사고 대비용 안전 사본 1본으로 대피 보관
    local current_targets=()
    [[ -d "${gemini_root}/antigravity" ]] && current_targets+=("antigravity")
    [[ -d "${gemini_root}/antigravity-cli" ]] && current_targets+=("antigravity-cli")
    if [[ "${#current_targets[@]}" -gt 0 ]]; then
        (umask 077 && tar -czf "${safety_path}" -C "${gemini_root}" "${current_targets[@]}") || true
        chmod 600 "${safety_path}" 2>/dev/null || true
    fi

    # 무결성 검증 통과 후 통합 디렉토리를 비우고 도입 전 원본으로 교체 복원
    rm -rf "${gemini_root}/antigravity" "${gemini_root}/antigravity-cli"

    if [[ -f "${archive_path}" ]]; then
        tar -xzf "${archive_path}" -C "${gemini_root}"
        rm -f "${archive_path}"
        caw_info "에이전트 DB·세션 디렉토리 도입 이전 상태(분리 원형) 복원 완료."
    else
        caw_info "도입 전 빈 환경 기준에 맞춰 에이전트 세션 디렉토리 초기화 완료."
    fi
}
