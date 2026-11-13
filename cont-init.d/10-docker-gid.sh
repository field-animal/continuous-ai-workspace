#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 10 - 호스트 Docker 소켓 GID 자동 매핑
# 목적: CAW_ENABLE_DOOD=true 일 때만 컨테이너 사용자(abc)에 소켓 그룹 권한을 부여함
# 비고: 독립 모듈이므로 본 파일을 제거하거나 CAW_ENABLE_DOOD=false 이면 동작하지 않음
# =============================================================================
set -euo pipefail

if [[ "${CAW_ENABLE_DOOD:-false}" != "true" ]]; then
    echo "[caw-init:10-docker-gid] CAW_ENABLE_DOOD 비활성화 상태 - 매핑을 건너뜁니다."
    exit 0
fi

DOCKER_SOCK="/var/run/docker.sock"
TARGET_USER="abc"

if [[ ! -S "${DOCKER_SOCK}" ]]; then
    echo "[caw-init:10-docker-gid] 경고: 소켓(${DOCKER_SOCK})이 존재하지 않습니다." >&2
    exit 1
fi

DOCKER_GID="$(stat -c '%g' "${DOCKER_SOCK}")"
if [[ ! "${DOCKER_GID}" =~ ^[0-9]+$ ]]; then
    echo "[caw-init:10-docker-gid] 오류: 유효하지 않은 소켓 GID(${DOCKER_GID})" >&2
    exit 1
fi

DOCKER_GROUP="$(getent group "${DOCKER_GID}" | cut -d: -f1 || true)"
if [[ -z "${DOCKER_GROUP}" ]]; then
    DOCKER_GROUP="dockersock"
    groupadd -g "${DOCKER_GID}" "${DOCKER_GROUP}"
    echo "[caw-init:10-docker-gid] 그룹 생성 완료: ${DOCKER_GROUP} (GID=${DOCKER_GID})"
fi

usermod -aG "${DOCKER_GROUP}" "${TARGET_USER}"
echo "[caw-init:10-docker-gid] 사용자(${TARGET_USER})에 Docker 소켓 권한 부여 완료"
