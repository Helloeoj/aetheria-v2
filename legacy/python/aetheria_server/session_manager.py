"""Track player sessions connected to the server."""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import Dict, List

from .protocol import Message, MessageType


@dataclass
class Session:
    session_id: str
    player_name: str
    outgoing: List[Message] = field(default_factory=list)


class SessionManager:
    def __init__(self) -> None:
        self.sessions: Dict[str, Session] = {}

    def create_local_session(self, player_name: str = "LocalHero") -> Session:
        session_id = f"local-{uuid.uuid4().hex[:8]}"
        session = Session(session_id=session_id, player_name=player_name)
        self.sessions[session_id] = session
        session.outgoing.append(
            Message(
                type=MessageType.HELLO,
                payload={"session_id": session_id, "player_name": player_name},
            )
        )
        return session

    def broadcast(self, message: Message) -> None:
        for session in self.sessions.values():
            session.outgoing.append(message)

    def flush_outgoing(self) -> Dict[str, List[str]]:
        emitted: Dict[str, List[str]] = {}
        for session_id, session in self.sessions.items():
            emitted[session_id] = [message.to_wire() for message in session.outgoing]
            session.outgoing.clear()
        return emitted


__all__ = ["Session", "SessionManager"]
