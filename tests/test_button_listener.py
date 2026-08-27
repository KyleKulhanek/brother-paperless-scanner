import importlib.util
import pathlib
import unittest


PATH = pathlib.Path(__file__).parents[1] / "bin" / "ha_button_listener.py"
SPEC = importlib.util.spec_from_file_location("listener", PATH)
listener = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(listener)


class ButtonEventTests(unittest.TestCase):
    def test_action_topic_by_ieee(self):
        event = {"topic": "zigbee2mqtt/0xaabb/action", "payload": "single"}
        self.assertEqual(listener.button_action(event, "0xaabb", "Scanner"), "single")

    def test_json_action_by_name(self):
        event = {"topic": "zigbee2mqtt/scanner button", "payload": '{"action":"double"}'}
        self.assertEqual(listener.button_action(event, "0xaabb", "Scanner Button"), "double")

    def test_unrelated_device_is_ignored(self):
        event = {"topic": "zigbee2mqtt/other/action", "payload": "single"}
        self.assertIsNone(listener.button_action(event, "0xaabb", "Scanner"))

    def test_telemetry_without_action_is_ignored(self):
        event = {"topic": "zigbee2mqtt/0xaabb", "payload": '{"battery":90}'}
        self.assertIsNone(listener.button_action(event, "0xaabb", "Scanner"))

    def test_websocket_urls(self):
        self.assertEqual(listener.websocket_url("http://ha:8123/"), "ws://ha:8123/api/websocket")
        self.assertEqual(listener.websocket_url("https://ha.example"), "wss://ha.example/api/websocket")


if __name__ == "__main__":
    unittest.main()
