"""
World state container and rules for tick timing and tile-based movement.

This module avoids any UI dependencies so it can be reused by the Arcade
client, CLI simulators, or headless tests.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, List, Optional, Tuple

from aetheria_core.combat_engine import CombatEngine, CombatActor


@dataclass
class WorldState:
    player: Any
    monsters: List[Any] = field(default_factory=list)
    width: int = 300
    height: int = 300
    tick_duration: float = 0.6
    combat: CombatEngine = field(default_factory=CombatEngine)

    _last_tick_timestamp: float = field(default_factory=time.time, init=False)

    # --------------------------------------------------------
    # Actor registration helpers
    # --------------------------------------------------------
    def register_player_actor(self, actor: CombatActor) -> None:
        self.combat.register_actor(actor)

    def register_monster_actor(self, monster_obj: Any, actor: CombatActor) -> None:
        self.monsters.append(monster_obj)
        self.combat.register_actor(actor)

    def remove_monster(self, entity_id: str) -> None:
        self.monsters = [m for m in self.monsters if getattr(m, "entity_id", None) != entity_id]
        self.combat.remove_actor(entity_id)

    # --------------------------------------------------------
    # Tick handling
    # --------------------------------------------------------
    def tick_due(self, now: Optional[float] = None) -> bool:
        now = now or time.time()
        return (now - self._last_tick_timestamp) >= self.tick_duration

    def tick(self, now: Optional[float] = None) -> List[dict]:
        now = now or time.time()
        if not self.tick_due(now):
            return []

        self._last_tick_timestamp = now
        return self.combat.process_tick(self)

    # --------------------------------------------------------
    # Movement rules
    # --------------------------------------------------------
    def move_actor(self, entity_id: str, dx: int, dy: int) -> Tuple[int, int]:
        actor = self.combat.actors.get(entity_id)
        if actor is None:
            return 0, 0

        new_x = self._clamp(actor.x + dx, 0, self.width - 1)
        new_y = self._clamp(actor.y + dy, 0, self.height - 1)

        actor.x = new_x
        actor.y = new_y
        self._sync_entity_position(entity_id, new_x, new_y)
        return new_x, new_y

    def _sync_entity_position(self, entity_id: str, x: int, y: int) -> None:
        if getattr(self.player, "entity_id", None) == entity_id:
            setattr(self.player, "x", x)
            setattr(self.player, "y", y)
            return

        for monster in self.monsters:
            if getattr(monster, "entity_id", None) == entity_id:
                setattr(monster, "x", x)
                setattr(monster, "y", y)
                break

    @staticmethod
    def _clamp(value: int, min_value: int, max_value: int) -> int:
        if value < min_value:
            return min_value
        if value > max_value:
            return max_value
        return value
