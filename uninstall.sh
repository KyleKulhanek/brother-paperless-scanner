#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID == 0 )) || { echo 'Run as root.' >&2; exit 1; }

systemctl disable --now bps-ha-button.service bps-worker.path 2>/dev/null || true
rm -f /etc/systemd/system/bps-ha-button.service \
    /etc/systemd/system/bps-worker.path /etc/systemd/system/bps-worker.service \
    /usr/local/sbin/bps-ha-button /usr/local/sbin/bps-queue-scan \
    /usr/local/sbin/bps-escl-worker
systemctl daemon-reload
echo 'Programs and units removed. Configuration and scan work data were preserved.'
