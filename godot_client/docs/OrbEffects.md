# Staff orb enchantments

A plain Magic Orb gives a staff no status effect. An empowered orb supplies one
element through the crafted staff's `orb_element` metadata: `fire`, `ice`,
`lightning`, or `hurricane`. Changing equipment does not change the element of an
attack already fired or a spell already being cast.

## Approved effects

Each successful direct damaging staff hit has a 10% chance to apply its element.
The current playable wizard uses selected spells rather than magic autoattacks,
so both enchanted staff autoattack projectiles and direct damaging selected spell
hits are supported. A selected spell captures the equipped staff's element when
casting starts. Projectile spells roll on collision; area spells roll separately
for each successfully damaged target. A spell cast with no enchanted staff has
no orb effect. Healing, walls, knockback, misses, zero damage and damage over time
cannot proc an orb.

| Element | Effect | Duration |
| --- | --- | --- |
| Fire | Five burn ticks, each worth 10% of actual triggering hit damage | Five 0.6-second ticks / 3 seconds |
| Ice | Attack rate multiplied by 0.9 | 10 seconds |
| Lightning | Prevents attacking, casting and voluntary movement | Three 0.6-second ticks / 1.8 seconds |
| Hurricane | Effective Defense level multiplied by 0.9, rounded down, minimum 1 | 10 seconds |

There is one instance of each effect on a target across all attackers. A second
proc does not strengthen an active effect, refresh its timer or replace its
original source. Different elements can coexist. The older authored
`status_effects` label array is kept separate from these active timed effects.

## Combat behavior

Burn uses damage actually dealt after mitigation. Fractions accumulate between
its five ticks; each tick applies only the whole damage accumulated so far.
There is no forced one-damage minimum, no second mitigation pass, and no burn
proc recursion. For example, a hit of 3 produces five budgets of 0.3, dealing
one total damage after whole-point rounding. Burn uses the normal damage, skill
experience and death-event paths, retains its original attacker ID, and reports
death once so existing monster loot/despawn handling runs normally.

Ice lengthens a 1.8-second attack interval to 2.0 seconds. It also slows damaging
selected spell casts because those casts are the live wizard's attack path.
Healing and utility cast speeds are unaffected. Applying Ice adjusts the pending
attack/cast once; repeats do not add more delay. When Ice ends partway through a
frame, only the portion before expiry uses the slower rate. Monsters retain the
existing combat tick grid, with fractional scheduled attack ticks preserving a
0.9 average rate instead of rounding every attack interval up to four ticks.

Lightning blocks actual monster pursuit, player/world movement and attack/cast
paths. Existing cast progress pauses during paralysis. Status timers advance
before combat recovery; a large frame gives monster movement and pending player
attacks/casts only the unblocked remainder of that frame.

Hurricane changes the effective level used in melee defense calculations,
including existing cached defense rolls. It never changes the underlying skill,
experience, gear resistance or base defense level. The current ranged/magic
accuracy formulas do not consume Defense level; their existing formulas remain.

Active effects live on the target CombatActor, serialize as separate copied
state, and survive player equipment/stat refreshes. Target death and removal
clear that state. Removing a monster leaves no scheduled burn outside the actor
registry. No artwork or spell visuals are added here.

## Verification

Run Godot 4.5.1 with the project path and
`res://scenes/dev_tools/orb_combat_smoke.tscn` as the scene. The normal scene runner
is necessary because the combat scripts use the project's GameData autoload.

The test exercises real CombatEngine projectiles, selected spell casting, damage,
attack cadence, WorldState movement and death events. Its deterministic chance
samples cover all four 10% procs; other checks cover fractional/mitigated burn,
cross-attacker nonstacking and no refresh, captured equipment, direct area hits,
paralysis recovery, Ice expiry, full first/idle engagement attack intervals,
Hurricane with cached defense, death and removal.
