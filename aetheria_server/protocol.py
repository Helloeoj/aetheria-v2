"""Lightweight protocol helpers for messages exchanged with the server."""
from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict


class MessageType(str, Enum):
    HELLO = "hello"
    WORLD_STATE = "world_state"
    PLAYER_INPUT = "player_input"
    SYSTEM = "system"


@dataclass
class Message:
    """Simple message container with JSON serialization helpers."""

    type: MessageType
    payload: Dict[str, Any]

    def to_wire(self) -> str:
        return json.dumps({"type": self.type.value, "payload": self.payload})

    @classmethod
    def from_wire(cls, data: str) -> "Message":
        raw = json.loads(data)
        message_type = MessageType(raw.get("type", MessageType.SYSTEM))
        payload = raw.get("payload", {})
        return cls(type=message_type, payload=payload)


__all__ = ["Message", "MessageType"]
