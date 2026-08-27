# Brother Scan-to-PC experiments

This section records useful findings without presenting the panel integration as
solved. It is intended to save other investigators time.

## Observed architecture

Brother's `brscan-skey` package periodically registers a Linux machine as a
Scan-to-PC destination. On the tested brscan5 model, explicit registration with
`brscan-skey -a DEVICE_NAME` was necessary. A panel File action then sent a UDP
message to port 54925 containing fields similar to:

```text
TYPE=BR;BUTTON=SCAN;USER="DESTINATION";FUNC=FILE;HOST=HOST:54925;...
```

The vendor listener invokes the configured `FILE` command. Returning from that
command was not enough to clear the printer's “Connecting to PC” state: the
firmware appeared to expect a proprietary SANE/backend transaction.

Opening and closing the Brother SANE device—without calling `sane_start`—was
tested as a minimal handshake. It succeeded locally but did not clear the panel
state. Calling `sane_start` would risk consuming the ADF through the unreliable
vendor backend and is intentionally not part of this project.

## Descriptor leak

The tested `brscan-skey-exe` leaked UDP file descriptors during periodic
registration. After reaching the process soft limit, refresh attempts failed
with `Too many open files` and the destination disappeared from the printer.
A practical mitigation is a systemd timer that restarts the listener when its
descriptor count crosses a conservative threshold.

Example detection logic:

```bash
pid="$(pgrep -f '/opt/brother/scanner/brscan-skey/brscan-skey-exe' | head -n1)"
count="$(find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
if (( count >= 256 )); then
    systemctl restart brscan-skey.service
fi
```

Adapt the process owner, device name, and unit to your environment. The vendor
wrapper may fork/background itself, so verify the actual process and sockets.

## Why this is not in the installer

- Brother packages and behavior vary by model, generation, and region.
- The tested printer advertised the destination but still could not complete
  the proprietary session reliably.
- Brother software is proprietary and cannot be redistributed here.
- eSCL acquisition plus a physical Zigbee button solved the actual workflow
  without pretending the panel protocol was understood.

Contributions with packet captures stripped of private data, exact package and
firmware versions, or results from other models are welcome.
