"""Durable, local roadmap content and manual completion state (no code scanning)."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import adc

LOOPS = json.loads((Path(__file__).parent / 'roadmap/loops.json').read_text(encoding='utf-8'))
CORE = [
    ('population', 'World population', 'Authored enemy pockets + repeat spawns. Main scene currently starts with an empty monster list.'),
    ('objective', 'Goal → payoff', 'One visible objective, progress, return reward and next lead. Guaranteed basic progress alongside random drops.'),
    ('food', 'Food → survival', 'Eat action, heal amount and action timing. Food already drops; inventory currently offers Equip / Drop.'),
    ('mana', 'Mana → continued casting', 'Explicit recovery rule: safe rest, out-of-combat regeneration, or consumables. Capacity and spending already exist.'),
    ('defeat', 'Defeat → another attempt', 'Safe respawn, playable recovery state and clear loss rule. Proposed start: keep gear and XP.'),
    ('economy', 'Gold → useful choice', 'One vendor, sell surplus, buy food/rest. NPC commerce is planned; prices and active transactions remain to build.'),
    ('persistence', 'Achievement → permanence', 'Save/load skills, gear, inventory, gold and objective state. Current player progress is held in memory.'),
    ('feedback', 'Rules → understanding', 'Visible goal/reward notices, threat cues and recovery feedback. Extend existing health bars, effects and journal.'),
]
DEPTH = [
    ('encounters', 'Readable enemy roles', 'Change style, use cover, isolate a threat or retreat?'),
    ('production', 'One useful recipe', 'Gather and prepare supplies, or buy them?'),
    ('discovery', 'Discovery + shortcut', 'Take the known route or investigate a new landmark?'),
    ('collection', 'Named reward sources', 'Which creature helps complete my next equipment goal?'),
    ('storage', 'Carry/storage policy', 'Limit trips through supplies alone, or also inventory space? A bank is optional.'),
    ('ammunition', 'Ammunition policy', 'Consume, recover or abstract arrows? Quiver scaffolding is already present.'),
]
EXTRA = [
    ('starter', 'Starter state', 'Starter gear, usable meals, one parcel-recovery task and a marked destination.'),
    ('rest', 'Safe rest', 'A safe hub away from enemy pursuit, with a working recovery action.'),
    ('optional', 'Optional threat', 'A visible extra reward behind a tougher encounter, with a viable retreat.'),
    ('playtest', 'Full adventure playtest', 'A new player knows the goal, survives or recovers, uses a reward, reloads progress and wants another trip.'),
]
TASKS = {key: {'title': title, 'detail': detail} for key, title, detail in CORE + DEPTH + EXTRA}
LOOP_TASKS = {
    'expedition': ['starter', 'population', 'objective', 'food', 'mana', 'rest', 'defeat', 'persistence', 'feedback', 'playtest'],
    'economy': ['economy', 'food', 'rest'],
    'production': ['production', 'food'],
    'discovery': ['discovery', 'objective', 'persistence'],
    'mastery': ['encounters', 'optional', 'feedback'],
    'collection': ['collection', 'persistence'],
}
ADVENTURE = [
    ('Tavern · prepare', 'Starter gear, usable meals, one parcel-recovery task and a marked destination.'),
    ('Woodland · take a risk', 'A small goblin pocket tuned for a fresh character; fight, loot, eat and choose whether to continue.'),
    ('Optional threat · choose', 'A visible extra reward behind a tougher encounter, with a viable retreat.'),
    ('Tavern · cash in', 'Return the parcel for a guaranteed useful reward; sell surplus, rest and make a purchase.'),
    ('Next outing · repeat', 'Keep saved progress, receive a new lead and try another route or loadout.'),
]
BUILD = [
    ('Starter state + save/load + defeat recovery', '', ['starter', 'persistence', 'defeat']),
    ('One populated encounter pocket + food + safe rest', 'Include mana recovery from the start if Magic is in the slice.', ['population', 'food', 'rest', 'mana']),
    ('One objective + return reward + one vendor', '', ['objective', 'economy', 'feedback', 'optional']),
    ('Full adventure playtest with developer menus closed', '', ['playtest']),
    ('One recipe + one discovery + one encounter variation', '', ['production', 'discovery', 'encounters']),
]
CONCLUSIONS = [
    ('Pass condition', EXTRA[-1][2]),
    ('Defer', 'Broad professions, housing, guilds, raids and a large quest framework.'),
    ('Decide early', 'Whether shared play is essential. Networking architecture matters early; social content can follow the first repeatable adventure.'),
    ('Review later', 'Defense XP rewards taking damage; the 80-hour model needs content and real travel/recovery evidence.'),
]


class RoadmapStore:
    """Writes each click atomically; rejects broken files instead of resetting progress."""
    def __init__(self, path):
        self.path = Path(path)
        self.error = ''
        self.state = {'version': 1, 'completed': {}, 'view': 'loops', 'loop': 'expedition'}
        try:
            if self.path.exists():
                state = json.loads(self.path.read_text(encoding='utf-8'))
                if (not isinstance(state, dict) or state.get('version') != 1
                        or not isinstance(state.get('completed'), dict)
                        or any(not isinstance(value, str) for value in state['completed'].values())):
                    raise ValueError('Unrecognized roadmap progress format')
                self.state.update(state)
        except (OSError, ValueError) as error:
            self.error = f'Progress could not be loaded; the saved file has been left untouched. {error}'

    def done(self, key):
        return bool(self.state['completed'].get(key))

    def count(self, keys=None):
        keys = list(TASKS) if keys is None else list(keys)
        return sum(self.done(key) for key in keys), len(keys)

    def _save(self, candidate):
        if self.error:
            raise OSError(self.error)
        candidate['updated_at'] = adc.now()
        adc.atomic(self.path, candidate)
        self.state = candidate

    def set_done(self, key, done):
        if key not in TASKS:
            raise ValueError('Unknown roadmap task')
        candidate = copy.deepcopy(self.state)
        if done:
            candidate['completed'][key] = adc.now()
        else:
            candidate['completed'].pop(key, None)
        self._save(candidate)

    def set_view(self, view, loop):
        if view not in ('loops', 'mechanics', 'next') or loop not in LOOPS:
            raise ValueError('Unknown roadmap view')
        candidate = copy.deepcopy(self.state)
        candidate.update(view=view, loop=loop)
        self._save(candidate)
