"""World state representation shared across clients and server."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional, Any


@dataclass
class Tile:
    x: int
    y: int
    region: str
    biome: str
    danger_level: int
    description: str = ""
    safezone: bool = False
    npcs: List[str] = field(default_factory=list)
    services: List[str] = field(default_factory=list)
    enemies: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "x": self.x,
            "y": self.y,
            "region": self.region,
            "biome": self.biome,
            "danger_level": self.danger_level,
            "description": self.description,
            "safezone": self.safezone,
            "npcs": self.npcs,
            "services": self.services,
            "enemies": self.enemies,
        }


class World:
    def __init__(self, width: int = 300, height: int = 300) -> None:
        self.width = width
        self.height = height
        self.world_map: Dict[Tuple[int, int], Tile] = {}
        self._ticks: int = 0
        self._initialize_static_world()

    def add_tile(
        self,
        x: int,
        y: int,
        region: str,
        biome: str,
        danger_level: int,
        description: str = "",
        safezone: bool = False,
        npcs: Optional[List[str]] = None,
        services: Optional[List[str]] = None,
        enemies: Optional[List[str]] = None,
    ) -> None:
        tile = Tile(
            x=x,
            y=y,
            region=region,
            biome=biome,
            danger_level=danger_level,
            description=description,
            safezone=safezone,
            npcs=npcs or [],
            services=services or [],
            enemies=enemies or [],
        )
        self.world_map[(x, y)] = tile

    def get_tile(self, x: int, y: int) -> Optional[Tile]:
        return self.world_map.get((x, y))

    def tick(self) -> Dict[str, Any]:
        self._ticks += 1
        return {
            "tick": self._ticks,
            "towns": [tile.region for tile in self.world_map.values() if tile.safezone],
            "tiles": len(self.world_map),
        }

    def _initialize_static_world(self) -> None:
        self.add_tile(
            260,
            75,
            "Emberhold",
            "town",
            1,
            "Emberhold is a citadel of obsidian and flame. Carved into the very bones of a volcano, its streets glow with molten rivers that slither through basalt gutters. Blacksmiths chant over glowing forges, and red-robed sentries watch from flame-lit towers.",
            safezone=True,
            npcs=["Blacksmith", "Merchant", "Quest Giver", "Enchanter", "Jarlmog the Castle Wizard"],
            services=["shop", "quests", "crafting", "enchanting", "fast_travel"],
        )
        self.add_tile(
            60,
            240,
            "Frostmarch",
            "town",
            1,
            "Frostmarch rises from the tundra like a blade of ice — sharp, cold, and resolute. Snow-covered stone towers pierce the skies, and ever-burning braziers line the ramparts.",
            safezone=True,
            npcs=["Ice Trader", "Runeforge Smith"],
            services=["shop", "fast_travel", "quests"],
        )
        self.add_tile(
            30,
            60,
            "Whisperwind",
            "town",
            1,
            "Whisperwind is nestled among towering whitebark trees and drifting blossoms. Treehouses and rope bridges form its canopy streets, and the melodies of flutes echo through the leaves.",
            safezone=True,
            npcs=["Herbalist", "Scout Trainer"],
            services=["shop", "quests", "fast_travel"],
        )
        self.add_tile(
            270,
            250,
            "Hollowshade",
            "town",
            1,
            "Wrapped in mist and lit by lanterns that never go out, Hollowshade feels like a memory whispered from beyond.",
            safezone=True,
            npcs=["Ghost Seer", "Shade Alchemist"],
            services=["shop", "quests", "fast_travel"],
        )
        self.add_tile(
            150,
            150,
            "Ironvale",
            "town",
            1,
            "Ironvale is carved into the iron cliffs of the Redcrag Gorge. Chains and pulleys creak across its caverns as miners and smiths move gear and ore.",
            safezone=True,
            npcs=["Ore Buyer", "Gearmaster Grobnar"],
            services=["shop", "crafting", "fast_travel"],
        )
        self.add_tile(
            200,
            40,
            "Sunmere",
            "town",
            1,
            "Sunmere gleams like a coin tossed to the sea. Its harbors are filled with sails and spice-scented markets, and its golden buildings reflect the ocean light.",
            safezone=True,
            npcs=["Fisher King", "Seaside Mage"],
            services=["shop", "quests", "fast_travel"],
        )
        for x, y in [(259, 74), (261, 76), (263, 77), (58, 239), (61, 241), (33, 61), (31, 63), (150, 149), (151, 151)]:
            self.add_tile(x, y, "Wilderness", "plains", 2, enemies=["Goblin Scout", "Wild Wolf"])


__all__ = ["Tile", "World"]
