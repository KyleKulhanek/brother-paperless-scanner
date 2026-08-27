# Brother Paperless Scanner

Turn a network Brother multifunction printer into a reliable, one-button,
multipage document intake for [Paperless-ngx](https://docs.paperless-ngx.com/).

The project deliberately separates **triggering** from **acquisition**:

```text
Zigbee button → Zigbee2MQTT → Home Assistant → this listener
                                                │
                                                ▼
Brother ADF → eSCL / sane-airscan → multipage PDF → Paperless consume
```

Brother's Linux Scan-to-PC stack can successfully advertise a destination yet
fail during its proprietary handoff. The scanner's standards-based eSCL endpoint
is usually much more dependable. This project uses Home Assistant only to
observe the chosen button event; the scan itself goes directly from the host to
the scanner and then into Paperless.

## What is proven

- Color, multipage ADF acquisition over eSCL/sane-airscan
- Atomic PDF delivery into a Paperless consume directory
- A lock that prevents overlapping scans and duplicate button presses
- Zigbee2MQTT button events consumed through Home Assistant's authenticated
  WebSocket API—no MQTT broker password is required
- Reconnect with bounded backoff after Home Assistant or network interruptions
- Hardened systemd services and root-readable secret configuration

The original deployment used a Brother MFC-J1365DW, Debian, Home Assistant,
Zigbee2MQTT, and a Tuya button. Other eSCL-capable Brother devices should work,
but need testing.

## Requirements

- Debian or Ubuntu host with network reachability to the scanner and Paperless
- `sane-utils`, `sane-airscan`, `img2pdf`, `curl`, `util-linux`, Python 3
- `python3-websocket` when using the Home Assistant button
- Paperless consume directory mounted on the same host
- Home Assistant with its MQTT integration connected to Zigbee2MQTT
- A dedicated non-admin Home Assistant long-lived token

Install packages:

```bash
sudo apt update
sudo apt install sane-utils sane-airscan img2pdf curl util-linux python3-websocket
```

Confirm eSCL discovery before installing:

```bash
scanimage -L
```

## Installation

```bash
git clone https://github.com/KyleKulhanek/brother-paperless-scanner.git
cd brother-paperless-scanner
sudo ./install.sh
sudoedit /etc/brother-paperless-scanner/scanner.env
sudoedit /etc/brother-paperless-scanner/home-assistant.env
```

The installer refuses to continue until its unprivileged service account can
write to the configured consume directory. Grant access using the group/ACL
model appropriate for your Paperless installation; do not make it world-writable.

After configuration:

```bash
sudo ENABLE_HA_BUTTON=true ./install.sh
systemctl status bps-worker.path bps-ha-button.service
```

## Testing

First test without Home Assistant:

```bash
sudo -u paperless-scan /usr/local/sbin/bps-queue-scan manual
journalctl -f -t brother-paperless-scanner
```

Load multiple pages in the ADF before queueing. A successful run creates one PDF
in Paperless's consume directory. Once that works, press the paired button and
watch the same journal.

Run project tests with:

```bash
python3 -m unittest discover -s tests -v
shellcheck bin/*.sh install.sh uninstall.sh
```

## How it works

`bps-ha-button` subscribes to `zigbee2mqtt/#` through Home Assistant's WebSocket
API and filters events locally by the configured IEEE address or friendly name.
It never logs the token or MQTT payload. A matching action atomically changes a
request file watched by `bps-worker.path`.

The worker polls `/eSCL/ScannerStatus` until the device is idle and the ADF is
loaded. It then asks sane-airscan for every page as PNG, combines them losslessly
with `img2pdf`, and atomically moves the finished PDF into Paperless. Temporary
pages are removed even after failure. No partial PDF is exposed to Paperless.

## Security

- Never use an administrator Home Assistant token for the permanent listener.
- Never put credentials in URLs or commit `.env` files.
- The listener has no infrastructure write capability beyond its scan queue.
- The worker can write only its work directory and the Paperless consume path.
- The scanner's self-signed TLS certificate is accepted by default because many
  embedded eSCL implementations cannot use a locally trusted certificate. Keep
  scanner traffic on a trusted LAN/VLAN.

See [SECURITY.md](SECURITY.md) for reporting and deployment guidance.

## Brother front-panel Scan-to-PC

The original investigation also repaired a resource leak in Brother's
`brscan-skey` listener and reverse-engineered part of its panel callback. That
work is documented in [docs/brother-panel-experiments.md](docs/brother-panel-experiments.md),
but is not installed by default: the destination could be advertised, while the
printer still hung on “Connecting to PC.” The Home Assistant button path is the
tested production solution.

This project is unofficial and is not affiliated with Brother Industries,
Home Assistant, or Paperless-ngx. No proprietary Brother software is included.

## License

MIT. See [LICENSE](LICENSE).
