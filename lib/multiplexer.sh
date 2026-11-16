#!/usr/bin/env bash
# =============================================================================
# CAW 멀티플렉서 감지·설치·래퍼 동기화 독립 모듈 (lib/multiplexer.sh)
# 목적:
#   1) 호스트에 설치된 실제 멀티플렉서(zellij / tmux)를 감지하여 중복 실행 없이 1종만 선택
#   2) 미설치 상태에서 정책 A(대화형 선택 설치: tmux / zellij / none)를 수행
#   3) 선택된 1종에 대해서만 소켓 래퍼 심볼릭 링크 및 설정 브리지를 구성함
# =============================================================================

if [[ "${_CAW_MUX_LIB_LOADED:-0}" == "1" ]]; then
    return 0
fi
readonly _CAW_MUX_LIB_LOADED=1

# CAW 래퍼가 아닌 실제 호스트 네이티브 실행 파일 경로를 탐색하는 함수
caw_find_real_binary() {
    local stack_root="$1"
    local host_home="$2"
    local bin_name="$3"
    local wrapper_real
    wrapper_real="$(realpath -m "${stack_root}/bin/${bin_name}")"

    if [[ -x "${host_home}/.local/bin/${bin_name}.standalone" ]]; then
        realpath "${host_home}/.local/bin/${bin_name}.standalone"
        return 0
    fi

    local IFS=':'
    local d cand cand_real
    for d in ${PATH} "${host_home}/.local/bin" "${host_home}/.cargo/bin" "/usr/local/bin" "/usr/bin"; do
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

# 호스트 OS 패키지 매니저를 이용해 tmux 를 설치하는 함수 (대화형 sudo 사용)
caw_install_host_tmux() {
    local dry_run="${1:-0}"
    if [[ "${dry_run}" == "1" ]]; then
        caw_info "[DRY-RUN] 호스트 OS 패키지 매니저로 tmux 설치 예정"
        return 0
    fi

    caw_info "OS 패키지 매니저를 통해 호스트에 tmux 설치를 진행합니다 (sudo 권한 필요)."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y tmux
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y tmux
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm tmux
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add tmux
    else
        caw_err "지원되는 패키지 매니저(apt/dnf/yum/pacman/apk)를 찾을 수 없습니다. 수동으로 tmux를 설치하세요."
        return 1
    fi
}

# 호스트 ~/.local/bin 에 공식 정적 zellij 바이너리를 버전 고정 및 SHA-256 무결성 검증 후 설치하는 함수
caw_install_host_zellij() {
    local host_home="$1"
    local dry_run="${2:-0}"
    local zellij_ver="${CAW_ZELLIJ_VERSION:-v0.45.1}"
    local arch
    arch="$(uname -m)"

    if [[ ! "${zellij_ver}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        caw_err "유효하지 않은 CAW_ZELLIJ_VERSION 형식입니다 (예: v0.45.1): ${zellij_ver}"
        return 1
    fi

    local target_arch=""
    local pinned_v0451_sha256=""
    case "${arch}" in
        x86_64|amd64)
            target_arch="x86_64"
            pinned_v0451_sha256="40bcc2e03f5d5ae8e054e39f676081fe12ab70871506996ba595834c3718eefc"
            ;;
        aarch64|arm64)
            target_arch="aarch64"
            pinned_v0451_sha256="05f0802afadd53f8db9514e7cae53c9ae8432fed1b35b8294aa816ee3044a16b"
            ;;
        *)
            caw_err "자동 설치를 지원하지 않는 CPU 아키텍처입니다: ${arch}"
            return 1
            ;;
    esac

    local base_url="https://github.com/zellij-org/zellij/releases/download/${zellij_ver}"
    local archive_name="zellij-${target_arch}-unknown-linux-musl.tar.gz"
    local url="${base_url}/${archive_name}"
    local sha_url="${base_url}/zellij-${target_arch}-unknown-linux-musl.sha256sum"
    local dest="${host_home}/.local/bin/zellij"

    if [[ "${dry_run}" == "1" ]]; then
        caw_info "[DRY-RUN] 공식 정적 바이너리 다운로드 및 SHA-256 검증 예정 (${zellij_ver}): ${url} -> ${dest}"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
        caw_err "zellij 자동 설치 및 무결성 검증을 위해 curl, tar, sha256sum 명령이 필요합니다."
        return 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' RETURN

    caw_info "공식 GitHub 릴리스에서 zellij ${zellij_ver}(${target_arch}) 정적 아카이브를 내려받습니다..."
    curl -fsSL --proto '=https' --tlsv1.2 "${url}" -o "${tmp_dir}/${archive_name}"

    local expected_sha=""
    if [[ "${zellij_ver}" == "v0.45.1" ]]; then
        expected_sha="${pinned_v0451_sha256}"
    else
        curl -fsSL --proto '=https' --tlsv1.2 "${sha_url}" -o "${tmp_dir}/release.sha256sum"
        expected_sha="$(awk '{print $1; exit}' "${tmp_dir}/release.sha256sum")"
        if [[ ! "${expected_sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
            caw_err "공식 체크섬 파일에서 유효한 SHA-256 해시를 추출하지 못했습니다: ${sha_url}"
            return 1
        fi
    fi

    if ! printf '%s  %s\n' "${expected_sha}" "${tmp_dir}/${archive_name}" | sha256sum -c - >/dev/null; then
        caw_err "다운로드된 zellij 아카이브의 SHA-256 체크섬이 일치하지 않아 설치를 중단합니다."
        return 1
    fi

    # 경로 이탈(Tar Slip) 방지를 위해 검증 완료 후 단일 파일명(zellij)만 명시 추출
    tar -xzf "${tmp_dir}/${archive_name}" -C "${tmp_dir}" zellij
    mkdir -p "${host_home}/.local/bin"
    install -m 0755 "${tmp_dir}/zellij" "${dest}"
    caw_info "호스트 zellij(${zellij_ver}) SHA-256 검증 및 설치 완료: ${dest}"
}

# 정책 A 기반 활성 멀티플렉서 1종 결정 및 미설치 시 선택 설치 함수
# 결과: 전역 변수 CAW_RESOLVED_MUX 에 zellij | tmux | none 설정
caw_select_and_prepare_mux() {
    local stack_root="$1"
    local host_home="$2"
    local requested_mux="$3"
    local dry_run="${4:-0}"

    local has_zellij=""
    local has_tmux=""
    has_zellij="$(caw_find_real_binary "${stack_root}" "${host_home}" "zellij" || true)"
    has_tmux="$(caw_find_real_binary "${stack_root}" "${host_home}" "tmux" || true)"

    CAW_RESOLVED_MUX="none"

    case "${requested_mux}" in
        none)
            CAW_RESOLVED_MUX="none"
            caw_info "CAW_MULTIPLEXER=none 설정에 따라 멀티플렉서 연동을 비활성화합니다."
            return 0
            ;;
        zellij)
            if [[ -z "${has_zellij}" ]]; then
                caw_install_host_zellij "${host_home}" "${dry_run}"
            fi
            CAW_RESOLVED_MUX="zellij"
            return 0
            ;;
        tmux)
            if [[ -z "${has_tmux}" ]]; then
                caw_install_host_tmux "${dry_run}"
            fi
            CAW_RESOLVED_MUX="tmux"
            return 0
            ;;
        auto)
            # 이미 설치된 도구가 있으면 중복 설치 없이 그대로 채택 (둘 다 있으면 tmux/zellij 중 감지된 1종 사용)
            if [[ -n "${has_zellij}" && -z "${has_tmux}" ]]; then
                CAW_RESOLVED_MUX="zellij"
                caw_info "호스트에 설치된 zellij 감지됨 - zellij 단독 연동 모드로 설정합니다."
                return 0
            elif [[ -n "${has_tmux}" && -z "${has_zellij}" ]]; then
                CAW_RESOLVED_MUX="tmux"
                caw_info "호스트에 설치된 tmux 감지됨 - tmux 단독 연동 모드로 설정합니다."
                return 0
            elif [[ -n "${has_zellij}" && -n "${has_tmux}" ]]; then
                CAW_RESOLVED_MUX="tmux"
                caw_info "호스트에 tmux와 zellij가 모두 존재합니다. 기본으로 tmux 1종만 연동합니다 (변경하려면 .env 의 CAW_MULTIPLEXER 지정)."
                return 0
            fi

            # 둘 다 미설치된 경우 (정책 A: 대화형 선택 설치 프롬프트 제공, 비대화형/드라이런은 none 폴백)
            if [[ "${dry_run}" == "1" || ! -t 0 ]]; then
                caw_warn "설치된 멀티플렉서(tmux/zellij)가 없습니다. 비대화형/드라이런 환경이므로 none 모드로 진행합니다."
                CAW_RESOLVED_MUX="none"
                return 0
            fi

            printf '\n[CAW] 호스트에 설치된 터미널 멀티플렉서(tmux / zellij)가 없습니다.\n'
            printf '  1) tmux 설치   (OS 기본 패키지 매니저 사용, sudo 필요)\n'
            printf '  2) zellij 설치 (~/.local/bin 공식 정적 바이너리, sudo 불필요)\n'
            printf '  3) 설치 안 함  (none 모드 - 웹 IDE 및 에이전트 저장소 공유만 사용)\n'
            local choice=""
            read -r -p "선택하세요 [1/2/3, 기본값 3]: " choice
            case "${choice}" in
                1)
                    caw_install_host_tmux "${dry_run}"
                    CAW_RESOLVED_MUX="tmux"
                    ;;
                2)
                    caw_install_host_zellij "${host_home}" "${dry_run}"
                    CAW_RESOLVED_MUX="zellij"
                    ;;
                *)
                    caw_info "멀티플렉서 미설치(none) 모드로 진행합니다."
                    CAW_RESOLVED_MUX="none"
                    ;;
            esac
            ;;
    esac
}
