#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo 'Run this installer as root.' >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_dir=/etc/brother-paperless-scanner
service_user="${SERVICE_USER:-paperless-scan}"
service_group="${SERVICE_GROUP:-paperless-scan}"

for command in scanimage img2pdf curl flock python3; do
    command -v "$command" >/dev/null || {
        echo "Missing dependency: $command" >&2
        echo 'On Debian/Ubuntu: apt install sane-utils sane-airscan img2pdf curl util-linux python3-websocket' >&2
        exit 1
    }
done

if ! getent group "$service_group" >/dev/null; then
    groupadd --system "$service_group"
fi
if ! id "$service_user" >/dev/null 2>&1; then
    useradd --system --gid "$service_group" --home-dir /nonexistent --shell /usr/sbin/nologin "$service_user"
fi

install -d -o root -g "$service_group" -m 0750 "$config_dir"
if [[ ! -e "$config_dir/scanner.env" ]]; then
    install -o root -g "$service_group" -m 0640 "$root/config/scanner.env.example" "$config_dir/scanner.env"
    echo "Created $config_dir/scanner.env — edit it before starting services."
fi
if [[ ! -e "$config_dir/home-assistant.env" ]]; then
    install -o root -g "$service_group" -m 0640 "$root/config/home-assistant.env.example" "$config_dir/home-assistant.env"
fi

# shellcheck source=/dev/null
source "$config_dir/scanner.env"
: "${SCAN_WORK:?Set SCAN_WORK in scanner.env}"
: "${PAPERLESS_CONSUME:?Set PAPERLESS_CONSUME in scanner.env}"

install -d -o "$service_user" -g "$service_group" -m 2770 "$SCAN_WORK"
if [[ ! -d "$PAPERLESS_CONSUME" ]]; then
    echo "Paperless consume directory does not exist: $PAPERLESS_CONSUME" >&2
    exit 1
fi
if ! runuser -u "$service_user" -- test -w "$PAPERLESS_CONSUME"; then
    echo "$service_user cannot write to $PAPERLESS_CONSUME." >&2
    echo "Grant the service account access without changing Paperless ownership, then rerun." >&2
    exit 1
fi

install -o root -g root -m 0755 "$root/bin/queue-scan.sh" /usr/local/sbin/bps-queue-scan
install -o root -g root -m 0755 "$root/bin/escl-worker.sh" /usr/local/sbin/bps-escl-worker
install -o root -g root -m 0755 "$root/bin/ha_button_listener.py" /usr/local/sbin/bps-ha-button

render_unit() {
    sed -e "s|@SERVICE_USER@|$service_user|g" \
        -e "s|@SERVICE_GROUP@|$service_group|g" \
        -e "s|@SCAN_WORK@|$SCAN_WORK|g" \
        -e "s|@PAPERLESS_CONSUME@|$PAPERLESS_CONSUME|g" \
        "$1" >"$2"
    chmod 0644 "$2"
}
render_unit "$root/systemd/bps-worker.path" /etc/systemd/system/bps-worker.path
render_unit "$root/systemd/bps-worker.service" /etc/systemd/system/bps-worker.service
render_unit "$root/systemd/bps-ha-button.service" /etc/systemd/system/bps-ha-button.service

systemctl daemon-reload
systemctl enable --now bps-worker.path
if [[ "${ENABLE_HA_BUTTON:-false}" == true ]]; then
    systemctl enable --now bps-ha-button.service
fi

echo 'Installation complete.'
echo 'Test with: sudo -u '"$service_user"' /usr/local/sbin/bps-queue-scan manual'
