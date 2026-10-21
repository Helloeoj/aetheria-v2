"""Entry point for running a lightweight server loop."""
from __future__ import annotations

import time
from typing import Iterable

from .session_manager import SessionManager
from .world_manager import WorldManager


def _log_emissions(emissions: Iterable[str]) -> None:
    for encoded in emissions:
        print(f"[EMIT] {encoded}")


def main() -> None:
    session_manager = SessionManager()
    world_manager = WorldManager(session_manager)

    local_session = session_manager.create_local_session(player_name="LocalTestPlayer")
    print(f"Started local session {local_session.session_id} for {local_session.player_name}")

    for _ in range(3):
        snapshot = world_manager.tick()
        emissions = session_manager.flush_outgoing()
        print(f"Tick {snapshot['tick']} processed with {len(world_manager.world.world_map)} tiles available")
        for session_id, messages in emissions.items():
            print(f"Session {session_id} outgoing:")
            _log_emissions(messages)
        time.sleep(0.05)


if __name__ == "__main__":
    main()
