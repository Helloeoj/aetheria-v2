# Longsword and warmaul combat reference

Research guide, 2026-11-04. Mechanics verified against indexed OSRS Wiki text;
direct wiki page/media access was blocked. The user-supplied scimitar GIF was
downloaded and inspected frame by frame. Animation directions below are proposed
Aetheria adaptations, not claims that RuneScape gives each option a unique clip.
This document does not mean the gameplay changes have been implemented.

## Sources

- [Combat Options](https://oldschool.runescape.wiki/w/Combat_Options): melee XP,
  invisible stance boosts, and attack types versus opponent defence.
- [Slash weapons, slash swords](https://oldschool.runescape.wiki/w/Slash_weapons):
  Chop / Slash / Lunge / Block options for standard longswords.
- [Granite maul](https://oldschool.runescape.wiki/w/Granite_maul): three crush options.
- [Animation category](https://oldschool.runescape.wiki/w/Category:Animations):
  the user's general reference index; direct access currently blocked.
- [Special attack animations](https://oldschool.runescape.wiki/w/Category:Special_attack_animations):
  reference for weight and follow-through, not permission to add special mechanics.
- [User-supplied scimitar attack GIF](https://user-images.githubusercontent.com/38588890/224814530-f68efe02-85b3-4936-a975-4e665d2e4dce.gif):
  inspected directly, 100 frames / 5 seconds. It contains combat and recovery,
  so the whole recording is not one attack's animation duration.

### Observations from the scimitar GIF

During its first attack the character starts in guard (0.0-0.2 s), raises the
blade above/across the shoulder (roughly 0.4-0.6 s), extends the weapon arm
through the cut (roughly 0.8 s), and returns to guard (roughly 1.0-1.4 s).
These are observed recording timestamps, not Aetheria timing settings.

Use the readable windup -> fast cutting arc -> recovery as the sword motion
reference. The body remains recognizable throughout: articulate the weapon arm
and allow a modest body turn rather than replacing or distorting the chest.
Keep feet grounded unless a specifically authored lunge calls for a step.
Adapt the phases to the existing attack interval. Do not copy special-attack
damage modifiers, extra hits, energy costs or effects into the ordinary styles.

## Mechanics mapping

XP entries are per point of actual damage, not attempted damage or overkill.
Every listed option also awards approximately 1.33 Health XP per damage.
Retain fractional rewards rather than flooring each small hit independently.
These are the requested RuneScape reference rates; replacing Aetheria's current
rates is part of the pending implementation, not a change to level curves.

| Weapon | Aetheria option | Damage type | Stance | Training XP/damage | Effective skill boost |
| --- | --- | --- | --- | --- | --- |
| Longsword | Chop | Slash | Accurate | 4 Attack | +3 Attack |
| Longsword | Slash | Slash | Aggressive | 4 Strength | +3 Strength |
| Longsword | Lunge | Stab | Controlled | approximately 1.33 each Attack, Strength, Defence | +1 each Attack, Strength, Defence |
| Longsword | Defensive | Slash | Defensive | 4 Defence | +3 Defence |
| Warmaul | Whack | Crush | Accurate | 4 Attack | +3 Attack |
| Warmaul | Batter | Crush | Aggressive | 4 Strength | +3 Strength |
| Warmaul | Defensive | Crush | Defensive | 4 Defence | +3 Defence |

Naming choice: Whack maps to the wiki's Pound; Batter maps to Pummel.
Defensive maps to the wiki's Block, but remains a damaging attack that trains
Defence. It must not become a shield block, parry, immunity action, or XP for
absorbing damage. Shields continue supplying their ordinary equipment defence.

The boosts apply to effective combat levels in the relevant accuracy, maximum
hit and defence calculations. They do not permanently raise saved skill levels,
add three flat damage, or guarantee an extra point of damage after rounding.
Slash/stab/crush use the matching opponent defence. Existing attack speeds,
weapon reach, item stats, special attacks and level curves are outside this change.

## Animation direction: original Aetheria motions

Author one distinct attack per listed option on Bronze, then share that same
motion with corresponding material tiers, using each tier's separate artwork.

| Option | Proposed motion |
| --- | --- |
| Longsword Chop | Compact downward diagonal cut; short, deliberate recovery. |
| Longsword Slash | Broader lateral cut across the target; stronger follow-through. |
| Longsword Lunge | Point-first forward thrust and straight withdrawal. |
| Longsword Defensive | Tight cut from a guarded stance, returning promptly to guard. |
| Warmaul Whack | Controlled short two-handed crush swing and quick reset. |
| Warmaul Batter | Larger two-handed overhead crush with pronounced follow-through. |
| Warmaul Defensive | Compact two-handed crush, returning the weapon close to guard. |

Preserve the complete head, torso, shoulders, legs and feet. Keep the weapon a
separate object. Both maul hands stay on its shaft; the longsword uses its weapon
hand while the shield follows the other arm. Defensive attacks still strike.
Use windup, contact and recovery inside the existing attack cadence. Animate
misses too; never award damage or XP just because an animation reached contact.
Verify the actual map player, including side/back views, armor off/on and walking.

## Current game integration gaps

- `PlayerState.attack_style` currently selects damage type (slash/stab/blunt),
  not the training option. Keep damage type separate from stance and animation.
  Map the existing internal `blunt` identifier to displayed Crush.
- `CombatSystem._skill_experience_events_for_hit` currently awards Attack and
  Strength together for melee hits, and Defence for taking damage. The requested
  stance rules need a targeted replacement of that routing.
- Effective-level boosts must feed existing combat formula inputs, not be
  represented by changing persistent skill levels or equipment bonuses.
- The attack event and animation must carry the selected option. Use the option
  at attack execution, so switching later cannot redirect that attack's XP.
- Update the existing selector, saves and authority validation consistently;
  preserve login, character progression and existing combat controls.

Acceptance requires distinct visible attack motions, correct actual-damage XP
including fractional accumulation, correct effective-level boosts, legal options
per weapon, and unchanged attack cooldowns. Research alone is not completion.
