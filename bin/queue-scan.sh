#!/usr/bin/env bash
set -Eeuo pipefail
umask 007

CONFIG_FILE="${SCANNER_CONFIG:-/etc/brother-paperless-scanner/scanner.env}"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

request="${SCAN_WORK}/scan-request"
source_name="${1:-external}"

mkdir -p "$SCAN_WORK"
tmp="$(mktemp "${request}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s pid=%s source=%q\n' "$(date --iso-8601=seconds)" "$$" "$source_name" >"$tmp"
mv -f "$tmp" "$request"
trap - EXIT
logger -t brother-paperless-scanner "Queued scan from ${source_name}"
