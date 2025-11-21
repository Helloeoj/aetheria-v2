"""Manage the shared world state and ticking logic."""
from __future__ import annotations

from typing import Dict, Any

from aetheria_core.world import World

from .protocol import Message, MessageType
from .session_manager import SessionManager


class WorldManager:
    def __init__(self, session_manager: SessionManager) -> None:
        self.world = World()
        self.session_manager = session_manager

    def tick(self) -> Dict[str, Any]:
        snapshot = self.world.tick()
        self.session_manager.broadcast(Message(type=MessageType.WORLD_STATE, payload=snapshot))
        return snapshot


__all__ = ["WorldManager"]
