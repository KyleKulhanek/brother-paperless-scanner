#!/usr/bin/env bash
set -Eeuo pipefail
umask 007

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONFIG_FILE="${SCANNER_CONFIG:-/etc/brother-paperless-scanner/scanner.env}"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${SCANNER_HOST:?SCANNER_HOST is required}"
: "${ESCL_DEVICE:?ESCL_DEVICE is required}"
: "${PAPERLESS_CONSUME:?PAPERLESS_CONSUME is required}"
: "${SCAN_WORK:?SCAN_WORK is required}"

ESCL_SCHEME="${ESCL_SCHEME:-https}"
ESCL_PORT="${ESCL_PORT:-443}"
SCAN_SOURCE="${SCAN_SOURCE:-ADF}"
SCAN_MODE="${SCAN_MODE:-Color}"
SCAN_RESOLUTION="${SCAN_RESOLUTION:-300}"
READY_MAX_POLLS="${READY_MAX_POLLS:-90}"
READY_POLL_SECONDS="${READY_POLL_SECONDS:-2}"
READY_POLLS_REQUIRED="${READY_POLLS_REQUIRED:-2}"

status_url="${ESCL_SCHEME}://${SCANNER_HOST}:${ESCL_PORT}/eSCL/ScannerStatus"
lockfile="${SCAN_WORK}/worker.lock"

mkdir -p "$SCAN_WORK"
exec 9>"$lockfile"
if ! flock -n 9; then
    logger -t brother-paperless-scanner 'A scan is already running; duplicate request ignored'
    exit 75
fi

if [[ ! -d "$PAPERLESS_CONSUME" || ! -w "$PAPERLESS_CONSUME" ]]; then
    logger -t brother-paperless-scanner "Consume directory is unavailable: $PAPERLESS_CONSUME"
    exit 1
fi

jobdir="$(mktemp -d "${SCAN_WORK}/job.XXXXXX")"
partial=''
cleanup() {
    rm -rf "$jobdir"
    [[ -z "$partial" ]] || rm -f "$partial"
}
trap cleanup EXIT

status_xml="${jobdir}/scanner-status.xml"
scan_error="${jobdir}/scan-error.log"

read_status() {
    local code
    local curl_tls=()
    [[ "$ESCL_SCHEME" != https ]] || curl_tls+=(--insecure)
    code="$(curl --silent --show-error "${curl_tls[@]}" --max-time 5 \
        --output "$status_xml" --write-out '%{http_code}' "$status_url" 2>/dev/null || true)"
    if [[ "$code" != 200 ]]; then
        printf 'HTTP_%s|UNKNOWN\n' "${code:-ERROR}"
        return
    fi
    python3 - "$status_xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    print("INVALID_XML|UNKNOWN")
    raise SystemExit

values = {"State": "UNKNOWN", "AdfState": "UNKNOWN"}
for element in root.iter():
    name = element.tag.rsplit("}", 1)[-1]
    text = (element.text or "").strip()
    if name in values and values[name] == "UNKNOWN" and text:
        values[name] = text
print(f"{values['State']}|{values['AdfState']}")
PY
}

logger -t brother-paperless-scanner 'Waiting for scanner readiness'
ready=0
last=''
for ((poll=1; poll<=READY_MAX_POLLS; poll++)); do
    status="$(read_status)"
    state="${status%%|*}"
    adf="${status#*|}"
    if [[ "$status" != "$last" ]]; then
        logger -t brother-paperless-scanner "eSCL status: state=${state}, adf=${adf}"
        last="$status"
    fi
    if [[ "${state,,}" == *idle* && "${adf,,}" == *loaded* && "${adf,,}" != *empty* ]]; then
        ((ready+=1))
        (( ready < READY_POLLS_REQUIRED )) || break
    else
        ready=0
    fi
    sleep "$READY_POLL_SECONDS"
done

if (( ready < READY_POLLS_REQUIRED )); then
    logger -t brother-paperless-scanner "Timed out waiting for scanner readiness; last=${last}"
    exit 1
fi

sleep 2
set +e
scanimage --device-name "$ESCL_DEVICE" --source "$SCAN_SOURCE" \
    --resolution "$SCAN_RESOLUTION" --mode "$SCAN_MODE" --format=png \
    --batch="${jobdir}/page-%04d.png" --batch-start=1 --batch-increment=1 \
    2>"$scan_error"
scan_status=$?
set -e

shopt -s nullglob
pages=("${jobdir}"/page-*.png)
if (( ${#pages[@]} == 0 )); then
    error_text="$(tail -n 20 "$scan_error" | tr '\n' ' ')"
    logger -t brother-paperless-scanner "Scan failed: no pages; status=${scan_status}; ${error_text}"
    exit 1
fi

stamp="$(date +'%Y-%m-%d_%H-%M-%S')"
base="scan_${stamp}_$$"
partial="${SCAN_WORK}/.${base}.partial.pdf"
final="${PAPERLESS_CONSUME}/${base}.pdf"
img2pdf "${pages[@]}" --output "$partial"
[[ -s "$partial" ]] || { logger -t brother-paperless-scanner 'PDF creation failed'; exit 1; }
chmod 0660 "$partial"
mv "$partial" "$final"
partial=''
logger -t brother-paperless-scanner "Created ${#pages[@]}-page PDF: $final"
