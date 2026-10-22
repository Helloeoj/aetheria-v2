"""Transport-independent social rules and durable development chat identities.

These profiles are separate from future gameplay accounts. Only credential
digests enter the database; credentials and message bodies must never be logged.
"""
from collections import OrderedDict
import hashlib
import math
import re
import sqlite3
import time
import unicodedata
import uuid


class SocialError(ValueError):
    pass


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, canonical TEXT NOT NULL UNIQUE,
                credential TEXT NOT NULL UNIQUE);
            CREATE TABLE IF NOT EXISTS relations (
                owner TEXT NOT NULL REFERENCES profiles(id),
                target TEXT NOT NULL REFERENCES profiles(id),
                kind TEXT NOT NULL CHECK(kind IN ('friend','block')),
                PRIMARY KEY(owner,target,kind), CHECK(owner != target));
        """)

    def close(self):
        self.db.close()

    def credential_owner(self, token):
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            return None
        digest = hashlib.sha256(token.encode()).hexdigest()
        row = self.db.execute("SELECT id FROM profiles WHERE credential=?", (digest,)).fetchone()
        return row["id"] if row else None

    def claim(self, name, token):
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_]{3,20}", name):
            raise SocialError("Use a name with 3-20 letters, numbers or underscores.")
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise SocialError("Invalid profile credential.")
        digest = hashlib.sha256(token.encode()).hexdigest()
        row = self.db.execute("SELECT * FROM profiles WHERE credential=?", (digest,)).fetchone()
        try:
            with self.db:
                if row:
                    self.db.execute("UPDATE profiles SET name=?, canonical=? WHERE id=?", (name, name.lower(), row["id"]))
                    return {"id": row["id"], "name": name}
                identity = uuid.uuid4().hex
                self.db.execute("INSERT INTO profiles VALUES (?,?,?,?)", (identity, name, name.lower(), digest))
                return {"id": identity, "name": name}
        except sqlite3.IntegrityError:
            raise SocialError("That name is unavailable. Choose another name.") from None

    def resolve(self, name):
        if not isinstance(name, str) or len(name) > 20:
            return None
        row = self.db.execute("SELECT id,name FROM profiles WHERE canonical=?", (name.strip().lower(),)).fetchone()
        return dict(row) if row else None

    def rows(self, owner, kind):
        return [dict(r) for r in self.db.execute(
            "SELECT p.id,p.name FROM relations r JOIN profiles p ON p.id=r.target "
            "WHERE r.owner=? AND r.kind=? ORDER BY p.canonical", (owner, kind))]

    def blocks(self, owner, target):
        return self.db.execute("SELECT 1 FROM relations WHERE owner=? AND target=? AND kind='block'", (owner, target)).fetchone() is not None

    def mutate(self, owner, target, kind, add):
        if owner == target:
            raise SocialError("You cannot add yourself.")
        with self.db:
            if add:
                if kind == "friend" and self.blocks(owner, target):
                    raise SocialError("Unblock this player before adding them as a friend.")
                existing = self.db.execute("SELECT 1 FROM relations WHERE owner=? AND target=? AND kind=?", (owner, target, kind)).fetchone()
                count = self.db.execute("SELECT COUNT(*) FROM relations WHERE owner=? AND kind=?", (owner, kind)).fetchone()[0]
                if not existing and count >= 200:
                    raise SocialError("This list is full (200 players).")
                if kind == "block":
                    self.db.execute("DELETE FROM relations WHERE owner=? AND target=? AND kind='friend'", (owner, target))
                self.db.execute("INSERT OR IGNORE INTO relations VALUES (?,?,?)", (owner, target, kind))
            else:
                self.db.execute("DELETE FROM relations WHERE owner=? AND target=? AND kind=?", (owner, target, kind))


class SocialService:
    def __init__(self, store, clock=time.monotonic, capacity=50):
        self.store = store
        self.clock = clock
        self.capacity = capacity
        self.peers = {}

    def join(self, name, token):
        if len(self.peers) >= self.capacity:
            raise SocialError("The chat server is full. Try again later.")
        if self.store.credential_owner(token) in self.peers:
            raise SocialError("This chat profile is already connected in another game.")
        profile = self.store.claim(name, token)
        identity = profile["id"]
        self.peers[identity] = {**profile, "location": None, "cache": OrderedDict(), "buckets": {}}
        return identity

    def leave(self, identity):
        self.peers.pop(identity, None)

    def snapshot(self, identity):
        friends = self.store.rows(identity, "friend")
        for friend in friends:
            friend["online"] = friend["id"] in self.peers and not self.blocked_pair(identity, friend["id"])
        friends.sort(key=lambda p: (not p["online"], p["name"].lower()))
        return {"type": "social", "friends": friends, "blocks": self.store.rows(identity, "block")}

    def snapshots(self):
        return [(p, self.snapshot(p)) for p in self.peers]

    def blocked_pair(self, a, b):
        return self.store.blocks(a, b) or self.store.blocks(b, a)

    def can_deliver(self, recipient, event):
        if recipient not in self.peers:
            return False
        if event.get("type") != "message":
            return True
        sender = event["sender_id"]
        if event["channel"] == "private":
            return not self.blocked_pair(sender, event["target_id"])
        return recipient == sender or not self.store.blocks(recipient, sender)

    def _limit(self, peer, key, rate, burst):
        now = self.clock()
        tokens, last = peer["buckets"].get(key, (float(burst), now))
        tokens = min(burst, tokens + max(0, now - last) * rate)
        if tokens < 1:
            raise SocialError("Please slow down before sending again.")
        peer["buckets"][key] = (tokens - 1, now)

    def _fresh(self, peer):
        loc = peer["location"]
        return loc is not None and self.clock() - loc["at"] <= 5

    def handle(self, identity, packet):
        request = ""
        try:
            if identity not in self.peers:
                raise SocialError("Reconnect to chat.")
            if not isinstance(packet, dict) or packet.get("v") != 1:
                raise SocialError("Unsupported chat protocol.")
            request = packet.get("request", "")
            if not isinstance(request, str) or not 1 <= len(request) <= 64:
                request = ""
                raise SocialError("Invalid request.")
            peer = self.peers[identity]
            self._limit(peer, "requests", 20, 40)
            now = self.clock()
            cache = peer["cache"]
            while cache and (len(cache) > 256 or now - next(iter(cache.values()))[0] > 60):
                cache.popitem(last=False)
            if request in cache:
                return [(identity, cache[request][1])]
            op = packet.get("op")
            fields = {"send": {"channel", "text", "target"}, "location": {"location"},
                      "friend_add": {"target"}, "friend_remove": {"target"},
                      "block_add": {"target"}, "block_remove": {"target"},
                      "snapshot": set(), "ping": set()}
            if not isinstance(op, str) or op not in fields or set(packet) - ({"v", "request", "op"} | fields[op]):
                raise SocialError("Invalid chat operation.")
            events = []
            result = {"type": "result", "request": request, "ok": True}
            if op == "location":
                self._limit(peer, "location", 3, 6)
                loc = packet.get("location")
                if loc is None:
                    peer["location"] = None
                else:
                    valid = isinstance(loc, dict) and set(loc) == {"world", "area", "instance", "x", "y"}
                    valid = valid and all(isinstance(loc[k], str) and 0 < len(loc[k]) <= 128 for k in ("world", "area", "instance"))
                    valid = valid and all(type(loc[k]) in (int, float) and math.isfinite(loc[k]) and abs(loc[k]) <= 1e7 for k in ("x", "y"))
                    if not valid:
                        raise SocialError("Invalid area position.")
                    peer["location"] = {**loc, "at": now}
            elif op.startswith("friend_") or op.startswith("block_"):
                self._limit(peer, "lists", 2, 10)
                target = self.store.resolve(packet.get("target"))
                if target is None:
                    raise SocialError("Player not found. They must connect to this server first.")
                kind, action = op.split("_")
                self.store.mutate(identity, target["id"], kind, action == "add")
                events.extend(self.snapshots())
            elif op == "snapshot":
                events.append((identity, self.snapshot(identity)))
            elif op == "send":
                self._limit(peer, "messages", 1, 5)
                text, channel = packet.get("text"), packet.get("channel")
                if not isinstance(text, str):
                    raise SocialError("Invalid message.")
                text = text.strip()
                if not 1 <= len(text) <= 280 or len(text.encode("utf-8")) > 1120 or any(unicodedata.category(c) in ("Cc", "Cs") for c in text):
                    raise SocialError("Use 1-280 characters on a single line.")
                target_id = ""
                target_name = ""
                if channel == "private":
                    target = self.store.resolve(packet.get("target"))
                    if target is None or target["id"] not in self.peers or target["id"] == identity or self.blocked_pair(identity, target["id"]):
                        raise SocialError("That player is unavailable for private messages.")
                    target_id, target_name = target["id"], target["name"]
                    recipients = [identity, target_id]
                elif channel == "global":
                    recipients = list(self.peers)
                elif channel == "local":
                    if not self._fresh(peer):
                        raise SocialError("Local chat is unavailable while changing areas. Use Global or Private.")
                    a = peer["location"]
                    recipients = []
                    for other_id, other in self.peers.items():
                        if not self._fresh(other):
                            continue
                        b = other["location"]
                        if all(a[k] == b[k] for k in ("world", "area", "instance")) and (a["x"]-b["x"])**2 + (a["y"]-b["y"])**2 <= 400:
                            recipients.append(other_id)
                else:
                    raise SocialError("Choose Local, Global or Private.")
                message = {"type": "message", "id": uuid.uuid4().hex, "request": request,
                           "channel": channel, "sender_id": identity, "sender": peer["name"],
                           "target_id": target_id, "target": target_name, "text": text, "time": int(time.time())}
                events.extend((p, message) for p in recipients if self.can_deliver(p, message))
                result["message_id"] = message["id"]
            cache[request] = (now, result)
            return events + [(identity, result)]
        except (SocialError, sqlite3.Error) as error:
            reason = str(error) if isinstance(error, SocialError) else "Chat storage is unavailable. Try again shortly."
            return [(identity, {"type": "result", "request": request, "ok": False, "error": reason})]
