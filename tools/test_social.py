"""Real domain/database and socket regressions for player communication."""
import asyncio
import json
import tempfile
import unittest
from pathlib import Path

try:
    from social_service import SocialService, Store, SocialError
except ImportError:
    SocialService = Store = SocialError = None


class SocialTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(Store, "The social service has not been implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "social.sqlite3"
        self.store = Store(self.path)
        self.addCleanup(lambda: self.store.close())
        self.now = 10.0
        self.service = SocialService(self.store, clock=lambda: self.now)
        self.a = self.service.join("Alice", "a" * 64)
        self.b = self.service.join("Bob", "b" * 64)
        self.c = self.service.join("Carol", "c" * 64)
        self.counter = 0

    def request(self, actor, op, **data):
        self.counter += 1
        return self.service.handle(actor, {"v": 1, "request": str(self.counter), "op": op, **data})

    def messages(self, events):
        return [(recipient, event) for recipient, event in events if event["type"] == "message"]

    def locate(self, actor, x=0, y=0, area="field", instance="main", world="dev"):
        return self.request(actor, "location", location={"world": world, "area": area, "instance": instance, "x": x, "y": y})

    def test_local_boundary_and_area_instance_world_isolation(self):
        self.locate(self.a)
        self.locate(self.b, 12, 16)
        self.locate(self.c, 20.01)
        events = self.messages(self.request(self.a, "send", channel="local", text="Hello"))
        self.assertEqual({p for p, _ in events}, {self.a, self.b})
        for key in ("area", "instance", "world"):
            self.locate(self.b, **{key: "elsewhere"})
            self.assertEqual(len(self.messages(self.request(self.a, "send", channel="local", text="Near?"))), 1)

    def test_global_crosses_areas_but_private_never_reaches_third_player(self):
        self.locate(self.b, area="tavern")
        self.assertEqual({p for p, _ in self.messages(self.request(self.a, "send", channel="global", text="Hello all"))}, {self.a, self.b, self.c})
        events = self.messages(self.request(self.a, "send", channel="private", target="bOb", text="Only Bob"))
        self.assertEqual({p for p, _ in events}, {self.a, self.b})
        self.assertEqual(len({e["id"] for _, e in events}), 1)

    def test_block_filters_public_and_prevents_private_both_directions(self):
        self.request(self.b, "friend_add", target="Alice")
        self.request(self.b, "block_add", target="Alice")
        self.assertEqual(self.service.snapshot(self.b)["friends"], [])
        events = self.messages(self.request(self.a, "send", channel="global", text="Public"))
        self.assertEqual({p for p, _ in events}, {self.a, self.c})
        self.assertEqual(self.messages(self.request(self.a, "send", channel="private", target="Bob", text="No")), [])
        self.assertEqual(self.messages(self.request(self.b, "send", channel="private", target="Alice", text="No")), [])
        self.request(self.b, "block_remove", target="Alice")
        self.assertEqual(self.service.snapshot(self.b)["friends"], [])

    def test_friends_are_unilateral_and_durable_across_server_restart(self):
        self.request(self.a, "friend_add", target="Bob")
        self.request(self.a, "friend_add", target="BOB")
        self.request(self.a, "block_add", target="Carol")
        self.assertEqual(len(self.service.snapshot(self.a)["friends"]), 1)
        self.assertEqual(self.service.snapshot(self.b)["friends"], [])
        self.store.close()
        self.store = Store(self.path)
        self.service = SocialService(self.store)
        alice = self.service.join("Alice", "a" * 64)
        snapshot = self.service.snapshot(alice)
        self.assertEqual([p["name"] for p in snapshot["friends"]], ["Bob"])
        self.assertFalse(snapshot["friends"][0]["online"])
        self.assertEqual([p["name"] for p in snapshot["blocks"]], ["Carol"])

    def test_identity_cannot_be_stolen_by_claiming_a_name(self):
        with self.assertRaises(SocialError):
            self.service.join("ALICE", "d" * 64)
        self.service.leave(self.a)
        self.assertEqual(self.service.join("Alice", "a" * 64), self.a)

    def test_rejected_duplicate_connection_does_not_rename_live_profile(self):
        with self.assertRaises(SocialError):
            self.service.join("ChangedName", "a" * 64)
        self.assertEqual(self.store.resolve("Alice")["id"], self.a)
        self.assertIsNone(self.store.resolve("ChangedName"))

    def test_queued_private_message_is_rechecked_after_block(self):
        events = self.messages(self.request(self.a, "send", channel="private", target="Bob", text="Queued"))
        self.request(self.b, "block_add", target="Alice")
        self.assertFalse(any(self.service.can_deliver(recipient, event) for recipient, event in events))

    def test_stale_or_travel_location_disables_local_but_not_global(self):
        self.locate(self.a)
        self.now += 6
        self.assertEqual(self.messages(self.request(self.a, "send", channel="local", text="Old")), [])
        self.assertEqual(len(self.messages(self.request(self.a, "send", channel="global", text="Online"))), 3)
        self.request(self.a, "location", location=None)
        self.assertEqual(self.messages(self.request(self.a, "send", channel="local", text="Travel")), [])

    def test_invalid_and_spoofed_packets_do_not_deliver(self):
        for data in ({"text": "x" * 281}, {"text": "one\ntwo"}, {"text": "ok", "sender": self.b}, {"text": "ok", "channel": "invented"}):
            packet = {"v": 1, "request": "bad", "op": "send", "channel": "global", "text": "ok", **data}
            self.assertEqual(self.messages(self.service.handle(self.a, packet)), [])
        events = self.locate(self.a, float("nan"))
        self.assertTrue(any(not event.get("ok", True) for _, event in events))

    def test_duplicate_request_and_rate_limit_do_not_duplicate_messages(self):
        packet = {"v": 1, "request": "same", "op": "send", "channel": "global", "text": "Once"}
        self.assertEqual(len(self.messages(self.service.handle(self.a, packet))), 3)
        self.assertEqual(self.messages(self.service.handle(self.a, packet)), [])
        for _ in range(4):
            self.request(self.a, "send", channel="global", text="Burst")
        self.assertEqual(self.messages(self.request(self.a, "send", channel="global", text="Too fast")), [])

    def test_blocked_friend_presence_and_self_actions(self):
        self.request(self.a, "friend_add", target="Bob")
        self.assertTrue(self.service.snapshot(self.a)["friends"][0]["online"])
        self.request(self.b, "block_add", target="Alice")
        self.assertFalse(self.service.snapshot(self.a)["friends"][0]["online"])
        for op in ("friend_add", "block_add"):
            events = self.request(self.a, op, target="Alice")
            self.assertTrue(any(not event.get("ok", True) for _, event in events))


if __name__ == "__main__":
    unittest.main(verbosity=2)
