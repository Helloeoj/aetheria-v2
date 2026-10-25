# Core Spellbook

This document records the agreed core wizard spell roster and current test-client
implementation for Aetheria. Spell data, unlock checks, and backend casting are
implemented; spell-specific visuals are still planned work.

## Elemental damage progression

The four elemental schools use a straightforward damage progression. Spells
primarily differ by damage, presentation, and animation. Area damage is
introduced progressively, with one elemental area spell unlocking at the end of
each tier.

| Tier | Fire | Water | Earth | Air | Area spell unlocked at tier end |
| --- | --- | --- | --- | --- | --- |
| 1 | Scorch | Undertow | Stonebite | Razorwind | Stormring (Air) |
| 2 | Searing Brand | Rushing Current | Hewn Stone | Cutting Wind | Tideburst (Water) |
| 3 | Blazing Comet | Crashing Tide | Falling Monolith | Rending Gale | Shatterground (Earth) |
| 4 | Sunfire | Leviathan's Surge | Mountain's Wrath | Tempest Crown | Cinderfall (Fire) |

## Arcane

Glimmer and Runic Force are earlier Arcane unlocks. Astral Lance and Starfall
are the final two spell unlocks, with Starfall last. Starfall is the only
Arcane area spell in the core roster.

- Glimmer — single-target damage
- Runic Force — single-target damage
- Astral Lance — single-target damage
- Starfall — area damage

**Aetherburst is not part of the spellbook.**

## Utility spells

These are special-purpose spells alongside the elemental damage ladders.

- Stoneward — creates a rock wall that blocks projectiles
- Mending Light — heals an ally
- Repelling Gust — knocks an enemy back

## Data foundation

The core spell definitions are stored in
[`data/spells.json`](../data/spells.json) and loaded by `GameData`. IDs are
stable machine identifiers; each definition includes its school, tier, damage,
range, mana cost, cast time, targeting shape, and effect kind. Special spells
also include their effect parameters, such as healing, wall duration, or
knockback distance. Numeric tuning values are placeholders, not balance
decisions. Utility spells use tier `0` because they are special unlocks outside
the elemental damage ladder; their Magic unlock levels are assigned below.

## Unlock schedule

Unlocks are gated by Magic level and spread across levels 1–100. The elemental
damage spells alternate Air, Water, Earth, Fire within each tier; each tier's
area spell follows its four damage spells. Arcane and utility spells are placed
between elemental milestones. The final unlocks are Astral Lance at level 96
and Starfall at level 100.

Area spells deal about 80% of the damage of the preceding single-target spell,
trading some damage per target for the ability to hit multiple enemies. Current
area damage values are Stormring 3, Tideburst 6, Shatterground 10, Cinderfall
16, and Starfall 28.

| Magic level | Spell |
| ---: | --- |
| 1 | Razorwind |
| 4 | Undertow |
| 7 | Stonebite |
| 10 | Scorch |
| 14 | Stormring |
| 16 | Glimmer |
| 18 | Stoneward |
| 22 | Cutting Wind |
| 26 | Rushing Current |
| 30 | Hewn Stone |
| 34 | Searing Brand |
| 38 | Tideburst |
| 42 | Runic Force |
| 46 | Rending Gale |
| 50 | Crashing Tide |
| 54 | Falling Monolith |
| 58 | Blazing Comet |
| 62 | Shatterground |
| 64 | Mending Light |
| 68 | Tempest Crown |
| 72 | Leviathan's Surge |
| 76 | Mountain's Wrath |
| 80 | Sunfire |
| 84 | Cinderfall |
| 88 | Repelling Gust |
| 96 | Astral Lance |
| 100 | Starfall |

Magic uses the shared 1–100 skill curve: level 90 starts at 9,725,000 XP and level
100 at 19,450,000 XP after the first 80-hour melee reference calibration. Magic's
casting pace still needs mana recovery and separate review. Magic XP comes from
successful spell casts and actual magic
damage; cast XP scales by unlock level from 10 XP at level 1 to 1,000 XP at
level 100. A fresh character starts at Magic level 1 and combat level 1. Enable
the main controller's optional `max_skills_for_testing` setting to start every
skill at 100, with combat level 150 and the complete spellbook available; the
setting defaults to off. See [`SkillProgression.md`](SkillProgression.md) for
the six skills, the five-skill combat level formula, XP sources, and current
reward values.

## Cast reliability

At a spell's unlock level, each casting attempt has a 20% chance to fail. Each
Magic level above the requirement reduces this by one percentage point, reaching
0% at 20 levels above the requirement. This applies to the entire spell roster,
including utility spells. A failed attempt spends the normal casting time and
mana and grants no cast XP or effect.

Casting failure is checked at completion using the player's current Magic level.
Mastery guarantees that the spell casts successfully; damage spells still use
their normal hit checks. With the level 100 cap, spells requiring more than
level 80 retain some cast failure chance, including Starfall at 20%.

## Test-client controls

- **Q/R** browse unlocked spells; **E** casts the selected spell.
- Casting uses the current enemy target for hostile and area spells. Mending
  Light targets the player when no ally is selected.
- Debug non-tester builds: Ctrl+Shift+V toggles provisional area-tile outlines,
  off by default. Preview and damage share the movement-grid footprint function;
  the cast locks its target cell when it starts. No final AoE sizes are approved.
  See [Hidden grid movement](HiddenGridMovement.md#aoe-design-amendment-and-phase-5)
  for placeholder radii, footprint counts and editable spell-data fields.

## Design guardrails

- Keep the listed spell names stable as the core roster is developed.
- Preserve the tier order and area-spell unlock order: Stormring, Tideburst,
  Shatterground, Cinderfall, then Starfall.
- Keep ordinary elemental spells focused on straightforward damage progression;
  reserve special effects for the listed utility spells and area damage.
- Damage, mana costs, cast times, area radii, and utility effect strengths are
  provisional tuning values and still need balancing.
