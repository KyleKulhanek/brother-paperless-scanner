#!/usr/bin/env python3
"""Queue eSCL scans from one Zigbee2MQTT device via Home Assistant."""

import json
import logging
import os
import subprocess
import time

import websocket


LOG = logging.getLogger("brother-paperless-scanner")


def websocket_url(http_url: str) -> str:
    scheme, rest = http_url.rstrip("/").split("://", 1)
    if scheme not in {"http", "https"}:
        raise ValueError("HA_URL must use http or https")
    return ("wss" if scheme == "https" else "ws") + "://" + rest + "/api/websocket"


def button_action(event: dict, ieee: str, name: str):
    topic = str(event.get("topic", "")).lower()
    text = str(event.get("payload", ""))
    if ieee.lower() not in topic and name.lower() not in topic:
        return None
    try:
        payload = json.loads(text)
    except (TypeError, ValueError):
        payload = None
    action = payload.get("action") if isinstance(payload, dict) else None
    if topic.endswith("/action"):
        action = text.strip('"')
    return str(action) if action else None


class Listener:
    def __init__(self):
        self.url = websocket_url(os.environ["HA_URL"])
        self.token = os.environ["HA_TOKEN"]
        self.ieee = os.environ["ZIGBEE_DEVICE_IEEE"]
        self.name = os.environ.get("ZIGBEE_DEVICE_NAME", "Paperless Scanner Button")
        self.cooldown = int(os.environ.get("BUTTON_COOLDOWN_SECONDS", "8"))
        self.queue = os.environ.get("QUEUE_COMMAND", "/usr/local/sbin/bps-queue-scan")

    def run_connection(self):
        ws = websocket.create_connection(self.url, timeout=45)
        try:
            if json.loads(ws.recv()).get("type") != "auth_required":
                raise RuntimeError("unexpected Home Assistant greeting")
            ws.send(json.dumps({"type": "auth", "access_token": self.token}))
            if json.loads(ws.recv()).get("type") != "auth_ok":
                raise RuntimeError("Home Assistant authentication rejected")
            ws.send(json.dumps({"id": 1, "type": "mqtt/subscribe", "topic": "zigbee2mqtt/#"}))
            result = json.loads(ws.recv())
            if result.get("type") != "result" or not result.get("success"):
                raise RuntimeError("MQTT subscription rejected")
            LOG.info("Connected to Home Assistant; waiting for configured button")
            last = 0.0
            while True:
                message = json.loads(ws.recv())
                if message.get("type") != "event" or message.get("id") != 1:
                    continue
                action = button_action(message.get("event", {}), self.ieee, self.name)
                now = time.monotonic()
                if action and now - last >= self.cooldown:
                    result = subprocess.run([self.queue, f"zigbee:{action}"], check=False, timeout=10)
                    if result.returncode:
                        LOG.error("Queue command failed with status %s", result.returncode)
                    else:
                        LOG.info("Queued scan from button action %s", action)
                        last = now
        finally:
            ws.close()

    def run_forever(self):
        delay = 2
        while True:
            try:
                self.run_connection()
                delay = 2
            except KeyboardInterrupt:
                return
            except Exception as exc:
                # Do not log URLs, payloads, or credentials.
                LOG.warning("Connection interrupted (%s); retrying in %ss", type(exc).__name__, delay)
                time.sleep(delay)
                delay = min(delay * 2, 60)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    Listener().run_forever()
