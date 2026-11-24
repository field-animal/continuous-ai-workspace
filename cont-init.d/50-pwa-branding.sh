#!/usr/bin/with-contenv bash
# =============================================================================
# CAW 컨테이너 기동 모듈 50 - PWA 앱 이름(iOS 타이틀 포함) 및 아이콘 브랜딩
# 목적:
#   1) PWA_APPNAME(CAW_PWA_APPNAME)에 맞춰 workbench.html의 apple-mobile-web-app-title 동기화
#   2) CAW_PWA_ICON 설정(로컬 파일, 디렉토리, HTTPS URL)에 따라 PWA 아이콘 및 파비콘 적용
#   3) 미설정·오프라인·포맷 오류 시에도 기본 아이콘으로 안전 복원하여 code-server 기동을 보장
# =============================================================================
set -euo pipefail

MEDIA_DIR="/app/code-server/src/browser/media"
WORKBENCH_HTML="/app/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html"
ORIG_BACKUP_DIR="/tmp/caw-pwa-orig"
ASSETS_DIR="/opt/caw/assets"
MAX_ICON_BYTES=5242880
MAX_SVG_BYTES=524288

STANDARD_ICON_FILES=(
    "pwa-icon-192.png"
    "pwa-icon-512.png"
    "pwa-icon-maskable-192.png"
    "pwa-icon-maskable-512.png"
    "favicon-dark-support.svg"
    "favicon.ico"
)

if [[ -x "/app/code-server/lib/node" ]]; then
    NODE_BIN="/app/code-server/lib/node"
elif command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
else
    echo "[caw-init:50-pwa-branding] [WARN] Node.js 실행 파일을 찾을 수 없어 PWA 브랜딩을 건너뜁니다." >&2
    exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR:-}"
}
trap cleanup EXIT

# 컨테이너 기동 세션 내 최초 1회만 원본 미디어 아이콘 및 workbench.html 백업 보관
backup_original_assets() {
    if [[ -d "${ORIG_BACKUP_DIR}" ]]; then
        return 0
    fi

    mkdir -p "${ORIG_BACKUP_DIR}/media"
    local fname
    for fname in "${STANDARD_ICON_FILES[@]}"; do
        if [[ -f "${MEDIA_DIR}/${fname}" ]]; then
            cp -p "${MEDIA_DIR}/${fname}" "${ORIG_BACKUP_DIR}/media/${fname}"
        fi
    done

    if [[ -f "${WORKBENCH_HTML}" ]]; then
        cp -p "${WORKBENCH_HTML}" "${ORIG_BACKUP_DIR}/workbench.html"
    fi
}

# CAW_PWA_ICON 미설정 또는 복구 필요 시 원본 아이콘 6종을 멱등 복원
restore_original_icons() {
    local fname
    for fname in "${STANDARD_ICON_FILES[@]}"; do
        if [[ -f "${ORIG_BACKUP_DIR}/media/${fname}" ]]; then
            install -m 0644 "${ORIG_BACKUP_DIR}/media/${fname}" "${MEDIA_DIR}/${fname}"
        fi
    done
}

# workbench.html의 apple-mobile-web-app-title 메타 태그를 PWA_APPNAME과 동기화
sync_apple_web_app_title() {
    local app_name="${PWA_APPNAME:-CAW}"
    local src_html="${ORIG_BACKUP_DIR}/workbench.html"
    if [[ ! -f "${src_html}" ]]; then
        src_html="${WORKBENCH_HTML}"
    fi
    if [[ ! -f "${src_html}" || ! -f "${WORKBENCH_HTML}" ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] workbench.html을 찾을 수 없어 iOS PWA 타이틀 동기화를 건너뜁니다." >&2
        return 0
    fi

    CAW_TARGET_TITLE="${app_name}" \
    CAW_SRC_HTML="${src_html}" \
    CAW_DST_HTML="${WORKBENCH_HTML}" \
    "${NODE_BIN}" -e '
const fs = require("fs");
const path = require("path");

const title = process.env.CAW_TARGET_TITLE || "CAW";
const srcPath = process.env.CAW_SRC_HTML;
const dstPath = process.env.CAW_DST_HTML;

const escaped = title
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/\x27/g, "&#39;");

const raw = fs.readFileSync(srcPath, "utf8");
const updated = raw.replace(
    /(<meta\s+name="apple-mobile-web-app-title"\s+content=")[^"]*(")/i,
    (_, p1, p2) => p1 + escaped + p2
);

const tmpOut = path.join(path.dirname(dstPath), `.workbench.html.tmp.${process.pid}`);
fs.writeFileSync(tmpOut, updated, { mode: 0o644 });
fs.renameSync(tmpOut, dstPath);
'
    echo "[caw-init:50-pwa-branding] PWA 앱 이름 동기화 완료: ${app_name}"
}

# CAW_PWA_ICON 입력(HTTPS URL, 컨테이너 절대경로, ./assets 상대경로)을 로컬 경로로 해석
resolve_icon_source() {
    local raw_spec="$1"

    # 제어문자 차단
    if [[ "${raw_spec}" =~ [[:cntrl:]] ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] CAW_PWA_ICON에 허용되지 않은 제어문자가 포함되어 있습니다." >&2
        return 1
    fi

    if [[ "${raw_spec}" == https://* ]]; then
        if [[ "${raw_spec}" =~ [[:space:]] ]]; then
            echo "[caw-init:50-pwa-branding] [WARN] CAW_PWA_ICON URL에 공백을 포함할 수 없습니다." >&2
            return 1
        fi
        if ! command -v curl >/dev/null 2>&1; then
            echo "[caw-init:50-pwa-branding] [WARN] curl 명령이 없어 원격 아이콘 다운로드를 건너뜁니다." >&2
            return 1
        fi
        local dl_file="${TMP_DIR}/downloaded-icon"
        if ! curl -fsSL --proto '=https' --tlsv1.2 \
            --connect-timeout 5 --max-time 15 \
            --max-filesize "${MAX_ICON_BYTES}" --max-redirs 3 \
            "${raw_spec}" -o "${dl_file}"; then
            echo "[caw-init:50-pwa-branding] [WARN] 원격 아이콘 다운로드 실패(기본 아이콘 유지): ${raw_spec}" >&2
            return 1
        fi
        printf '%s\n' "${dl_file}"
        return 0
    fi

    if [[ "${raw_spec}" == *://* ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] 보안상 원격 아이콘은 https:// URL만 허용됩니다: ${raw_spec}" >&2
        return 1
    fi

    # 경로 이탈(..) 차단
    if [[ "${raw_spec}" =~ (^|/)\.\.(/|$) ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] 상위 디렉토리 이동(..)이 포함된 경로는 허용되지 않습니다: ${raw_spec}" >&2
        return 1
    fi

    if [[ "${raw_spec}" == /* ]]; then
        local resolved_abs
        resolved_abs="$(realpath -m -- "${raw_spec}")"
        if [[ ! -e "${resolved_abs}" ]]; then
            echo "[caw-init:50-pwa-branding] [WARN] 지정한 아이콘 경로가 존재하지 않습니다: ${resolved_abs}" >&2
            return 1
        fi
        printf '%s\n' "${resolved_abs}"
        return 0
    fi

    # 상대경로: ./assets/ 또는 assets/ 접두사 허용 및 /opt/caw/assets 경계 고정
    local rel="${raw_spec#./}"
    rel="${rel%/}"
    if [[ "${rel}" == "assets" || "${rel}" == "." ]]; then
        rel=""
    else
        rel="${rel#assets/}"
    fi
    if [[ "${rel}" == "." ]]; then
        rel=""
    fi

    local resolved_root resolved_rel
    resolved_root="$(realpath -m -- "${ASSETS_DIR}")"
    if [[ -n "${rel}" ]]; then
        resolved_rel="$(realpath -m -- "${resolved_root}/${rel}")"
    else
        resolved_rel="${resolved_root}"
    fi

    if [[ "${resolved_rel}" != "${resolved_root}" && "${resolved_rel}" != "${resolved_root}/"* ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] assets 디렉토리 경계를 벗어난 경로입니다: ${raw_spec}" >&2
        return 1
    fi

    if [[ ! -e "${resolved_rel}" ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] assets 경로에서 아이콘을 찾을 수 없습니다: ${resolved_rel}" >&2
        return 1
    fi

    printf '%s\n' "${resolved_rel}"
    return 0
}

# 단일 파일 또는 특정 대상 파일에 대해 매직 바이트·크기·보안 검증 및 적용 수행
# 인자: $1=원본 파일 경로, $2=적용 모드(single | exact), $3=exact 모드일 때 대상 파일명
apply_icon_with_node() {
    local src_file="$1"
    local apply_mode="$2"
    local exact_target="${3:-}"

    CAW_ICON_SRC="${src_file}" \
    CAW_ICON_MODE="${apply_mode}" \
    CAW_ICON_EXACT_TARGET="${exact_target}" \
    CAW_MEDIA_DIR="${MEDIA_DIR}" \
    CAW_MAX_ICON_BYTES="${MAX_ICON_BYTES}" \
    CAW_MAX_SVG_BYTES="${MAX_SVG_BYTES}" \
    "${NODE_BIN}" -e '
const fs = require("fs");
const path = require("path");

const srcPath = process.env.CAW_ICON_SRC;
const mode = process.env.CAW_ICON_MODE;
const exactTarget = process.env.CAW_ICON_EXACT_TARGET || "";
const mediaDir = process.env.CAW_MEDIA_DIR;
const maxIconBytes = Number(process.env.CAW_MAX_ICON_BYTES || "5242880");
const maxSvgBytes = Number(process.env.CAW_MAX_SVG_BYTES || "524288");

function atomicWrite(dstPath, buf) {
    const tmpPath = path.join(path.dirname(dstPath), `.${path.basename(dstPath)}.tmp.${process.pid}`);
    fs.writeFileSync(tmpPath, buf, { mode: 0o644 });
    fs.chmodSync(tmpPath, 0o644);
    fs.renameSync(tmpPath, dstPath);
}

function buildSvgWrapper(pngBuf, w, h) {
    const b64 = pngBuf.toString("base64");
    return Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">` +
        `<image width="${w}" height="${h}" href="data:image/png;base64,${b64}"/>` +
        `</svg>\n`,
        "utf8"
    );
}

function validateSvgOrExit(buf, svgText, srcLabel) {
    if (buf.length > maxSvgBytes) {
        console.error(`[caw-init:50-pwa-branding] [WARN] SVG 크기가 제한(512KB)을 초과했습니다: ${srcLabel}`);
        process.exit(1);
    }
    const unsafePattern = /(<script\b|<\/script|javascript\s*:|vbscript\s*:|\bon[a-z]+\s*=|<foreignObject\b|data\s*:\s*text\/html)/i;
    if (unsafePattern.test(svgText)) {
        console.error(`[caw-init:50-pwa-branding] [WARN] 보안상 허용되지 않는 스크립트/이벤트 요소가 SVG에서 감지되어 거부되었습니다: ${srcLabel}`);
        process.exit(1);
    }
}

const stat = fs.statSync(srcPath);
if (!stat.isFile()) {
    console.error(`[caw-init:50-pwa-branding] [WARN] 일반 파일이 아닙니다: ${srcPath}`);
    process.exit(1);
}
if (stat.size === 0 || stat.size > maxIconBytes) {
    console.error(`[caw-init:50-pwa-branding] [WARN] 아이콘 파일 크기가 허용 범위(1B~5MB)를 벗어났습니다 (${stat.size} bytes): ${srcPath}`);
    process.exit(1);
}

const buf = fs.readFileSync(srcPath);
const isPng = buf.length >= 24 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47 &&
    buf[4] === 0x0d && buf[5] === 0x0a && buf[6] === 0x1a && buf[7] === 0x0a &&
    buf.slice(12, 16).toString("ascii") === "IHDR";

const isIco = buf.length >= 6 &&
    buf[0] === 0x00 && buf[1] === 0x00 && buf[2] === 0x01 && buf[3] === 0x00;

let isSvg = false;
let svgText = "";
if (!isPng && !isIco && !buf.includes(0x00)) {
    svgText = buf.toString("utf8");
    if (/<svg[\s>]/i.test(svgText)) {
        isSvg = true;
    }
}

if (mode === "exact") {
    if (exactTarget.endsWith(".png")) {
        if (!isPng) {
            console.error(`[caw-init:50-pwa-branding] [WARN] ${exactTarget} 파일은 유효한 PNG 형식이어야 합니다.`);
            process.exit(1);
        }
        const w = buf.readUInt32BE(16);
        const h = buf.readUInt32BE(20);
        if (w === 0 || h === 0) {
            console.error(`[caw-init:50-pwa-branding] [WARN] 잘못된 PNG 해상도입니다: ${exactTarget}`);
            process.exit(1);
        }
        atomicWrite(path.join(mediaDir, exactTarget), buf);
        console.log(`[caw-init:50-pwa-branding] 아이콘 매핑 적용: ${exactTarget} (${w}x${h} PNG)`);
        process.exit(0);
    }
    if (exactTarget === "favicon-dark-support.svg") {
        if (!isSvg) {
            console.error(`[caw-init:50-pwa-branding] [WARN] ${exactTarget} 파일은 유효한 SVG 형식이어야 합니다.`);
            process.exit(1);
        }
        validateSvgOrExit(buf, svgText, srcPath);
        atomicWrite(path.join(mediaDir, exactTarget), buf);
        console.log(`[caw-init:50-pwa-branding] SVG 파비콘 매핑 적용: ${exactTarget}`);
        process.exit(0);
    }
    if (exactTarget === "favicon.ico") {
        if (!isIco) {
            console.error(`[caw-init:50-pwa-branding] [WARN] ${exactTarget} 파일은 유효한 ICO 형식이어야 합니다.`);
            process.exit(1);
        }
        atomicWrite(path.join(mediaDir, exactTarget), buf);
        console.log(`[caw-init:50-pwa-branding] ICO 파비콘 매핑 적용: ${exactTarget}`);
        process.exit(0);
    }
    process.exit(1);
}

// single 모드: 1개 파일을 PWA 4종 및/또는 파비콘에 적용
if (isPng) {
    const w = buf.readUInt32BE(16);
    const h = buf.readUInt32BE(20);
    if (w === 0 || h === 0) {
        console.error(`[caw-init:50-pwa-branding] [WARN] 손상된 PNG IHDR 해상도입니다: ${srcPath}`);
        process.exit(1);
    }
    for (const target of [
        "pwa-icon-192.png",
        "pwa-icon-512.png",
        "pwa-icon-maskable-192.png",
        "pwa-icon-maskable-512.png"
    ]) {
        atomicWrite(path.join(mediaDir, target), buf);
    }
    atomicWrite(path.join(mediaDir, "favicon-dark-support.svg"), buildSvgWrapper(buf, w, h));
    console.log(`[caw-init:50-pwa-branding] PNG 아이콘 일괄 적용 완료 (${w}x${h}) -> PWA 4종 + SVG 파비콘 동기화`);
    if (w !== h || w < 192 || h < 192) {
        console.log(`[caw-init:50-pwa-branding] [INFO] 512x512 정사각형 PNG 사용을 권장합니다 (현재: ${w}x${h}).`);
    }
    process.exit(0);
}

if (isSvg) {
    validateSvgOrExit(buf, svgText, srcPath);
    atomicWrite(path.join(mediaDir, "favicon-dark-support.svg"), buf);
    console.log("[caw-init:50-pwa-branding] SVG 파비콘만 적용됨 - PWA 홈 화면 아이콘까지 변경하려면 512x512 PNG 또는 아이콘 디렉토리를 지정하세요.");
    process.exit(0);
}

if (isIco) {
    atomicWrite(path.join(mediaDir, "favicon.ico"), buf);
    console.log("[caw-init:50-pwa-branding] ICO 파비콘만 적용됨 - PWA 홈 화면 아이콘까지 변경하려면 512x512 PNG 또는 아이콘 디렉토리를 지정하세요.");
    process.exit(0);
}

console.error(`[caw-init:50-pwa-branding] [WARN] 지원하지 않는 아이콘 파일 형식입니다 (PNG, SVG, ICO만 지원): ${srcPath}`);
process.exit(1);
'
}

# 디렉토리 내 표준 아이콘 파일명별 1:1 매핑 적용 및 누락된 SVG 파비콘 자동 동기화
apply_icon_directory() {
    local dir_path="$1"
    local applied_count=0
    local applied_png=""
    local has_custom_svg=0
    local fname

    for fname in "${STANDARD_ICON_FILES[@]}"; do
        if [[ -f "${dir_path}/${fname}" ]]; then
            if apply_icon_with_node "${dir_path}/${fname}" "exact" "${fname}"; then
                applied_count=$((applied_count + 1))
                if [[ "${fname}" == "favicon-dark-support.svg" ]]; then
                    has_custom_svg=1
                elif [[ "${fname}" == *.png ]]; then
                    if [[ "${fname}" == "pwa-icon-512.png" || -z "${applied_png}" ]]; then
                        applied_png="${MEDIA_DIR}/${fname}"
                    fi
                fi
            fi
        fi
    done

    if [[ "${applied_count}" -eq 0 ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] 디렉토리(${dir_path})에 표준 아이콘 파일(pwa-icon-*.png, favicon-dark-support.svg, favicon.ico)이 없습니다." >&2
        return 1
    fi

    # PNG는 교체되었지만 favicon-dark-support.svg가 제공되지 않은 경우 PNG 기반 SVG 파비콘 자동 생성
    if [[ "${has_custom_svg}" -eq 0 && -n "${applied_png}" ]]; then
        CAW_ICON_SRC="${applied_png}" \
        CAW_DST_SVG="${MEDIA_DIR}/favicon-dark-support.svg" \
        "${NODE_BIN}" -e '
const fs = require("fs");
const path = require("path");
const buf = fs.readFileSync(process.env.CAW_ICON_SRC);
const w = buf.readUInt32BE(16);
const h = buf.readUInt32BE(20);
const dst = process.env.CAW_DST_SVG;
const svg = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">` +
    `<image width="${w}" height="${h}" href="data:image/png;base64,${buf.toString("base64")}"/>` +
    `</svg>\n`,
    "utf8"
);
const tmp = path.join(path.dirname(dst), `.favicon.svg.tmp.${process.pid}`);
fs.writeFileSync(tmp, svg, { mode: 0o644 });
fs.chmodSync(tmp, 0o644);
fs.renameSync(tmp, dst);
'
        echo "[caw-init:50-pwa-branding] 적용된 PNG 기반 SVG 파비콘 자동 동기화 완료."
    fi
}

main() {
    if [[ ! -d "${MEDIA_DIR}" ]]; then
        echo "[caw-init:50-pwa-branding] [WARN] 미디어 디렉토리를 찾을 수 없어 건너뜁니다: ${MEDIA_DIR}" >&2
        return 0
    fi

    backup_original_assets
    sync_apple_web_app_title

    local icon_spec="${CAW_PWA_ICON:-}"
    if [[ -z "${icon_spec}" ]]; then
        restore_original_icons
        echo "[caw-init:50-pwa-branding] CAW_PWA_ICON 미설정 - 기본 code-server 아이콘을 유지합니다."
        return 0
    fi

    local resolved_src=""
    if ! resolved_src="$(resolve_icon_source "${icon_spec}")"; then
        restore_original_icons
        return 0
    fi

    # 기존 커스텀 흔적이 남지 않도록 항상 원본 기준에서 덮어쓰기 시작
    restore_original_icons

    if [[ -d "${resolved_src}" ]]; then
        apply_icon_directory "${resolved_src}" || restore_original_icons
    else
        apply_icon_with_node "${resolved_src}" "single" || restore_original_icons
    fi
}

main "$@"
exit 0
