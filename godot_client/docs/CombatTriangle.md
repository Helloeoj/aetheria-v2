# Classless combat triangle

Implemented 2026-11-03. Armour primarily changes hit chance; it adds no player damage absorption. Skills persist when swapping weapons and armour. No classes, switching delays, item IDs, artwork, requirements, set-effect metadata or acquisition rules changed.

## Hit rolls

Player ranged and magic attacks now compare an offensive roll against the actual target's corresponding defence roll, using the existing melee hit-chance comparison and 5–99% bounds.

```text
attack roll = (offensive skill + 8) * max(0, 64 + style attack bonus)
              * max(0, 1 + generic equipment accuracy bonus)
physical defence roll = (Defence + 8) * 64 / (1 - armour resistance)
player magic defence roll = (0.7 * Magic + 0.3 * Defence + 8)
                            * 64 / (1 - magic armour resistance)
armour resistance = clamp(raw rating / (1 + abs(raw rating)), -0.5, 0.8)
```

Use raw equipment ratings for these rolls; do not also add the legacy skill-resistance contribution. Slash, stab and internal `blunt` (Crush) remain separate defence channels. Ranged uses Ranged skill offensively and Defence defensively; Ranged skill does not increase ranged defence. Magic remains available independently of the currently equipped weapon for selected spells.

Projectile damage and offensive rolls are captured at launch. Impact checks the current defences of the first actor actually struck, including intervening actors. Equipment changes cannot strengthen an arrow already in flight. Elemental and area spells use magic rolls. Hurricane affects only the Defence contribution, retaining equipment and trained Magic contributions.

Monster magic defence uses its authored Magic skill, falling back to the existing encounter level when absent, without a player-level cap. Existing authored monster non-melee attack accuracy and explicit `forced_accuracy` overrides retain their compatibility model; its player magic skill bonus now has the 70/30 weighting. This pass does not invent new offensive monster skills or rebalance every encounter. Existing golem damage absorption is retained separately.

## Existing armour

- Standard metal armour and shields retain their physical defence progression and existing negative magic defence. They receive magic/ranged attack penalties: helmet −6/−2, body −30/−15, legs −21/−11, shield −10/−5. Artifact melee sets receive negative magic defence in place of their former positive values.
- Tanned Leather now offers positive magic defence, less physical protection than same-tier plate, ranged attack bonuses and magic attack penalties.
- Existing artifact ranged sets offer the strongest magic protection of the three armour families, moderate physical protection, ranged attack bonuses and magic attack penalties.
- Existing artifact robes offer very low melee defence, zero ranged defence, positive magic accuracy and explicit magic damage bonuses: hood 4%, robe 10%, wraps 6% (20% together). These apply to automatic magic attacks and selected damaging spells. Utility/healing spells retain their definitions.

Body armour attack bonuses and penalties change accuracy, without acting as ranged strength or implicit spell damage. Existing weapon and accessory damage scaling remains intact. Equipment inspection displays the explicit magic damage bonus; battle readiness explains that hit chance depends on the target.

This establishes the equipment tradeoffs, rather than guaranteeing a winner independent of gear tier, skill, spell, weapon speed, movement and range. Exact encounter difficulty and damage-per-second still need player playtesting. No movement or kiting rules were changed.

## Reference and validation

OSRS reference: [Defence](https://oldschool.runescape.wiki/w/Defence), [Magic](https://oldschool.runescape.wiki/w/Magic), [platebodies](https://oldschool.runescape.wiki/w/Platebody), [black dragonhide](https://oldschool.runescape.wiki/w/Black_d%27hide_body), [Mystic robes](https://oldschool.runescape.wiki/w/Mystic_robes). Aetheria retains its own armour-rating scale rather than copying OSRS integer bonuses into fractional ratings.

Run `res://scenes/dev_tools/combat_triangle_smoke.tscn` with the installed Godot 4.5.1 engine. It covers skill weights, all five defence channels, armour-family tradeoffs, real seeded hits, selected spell damage, projectile collisions, swaps, serialization and the real main-scene actor adapters. Relevant existing regressions are bronze combat, Runite equipment and orb combat. Runite's old assertion that Defence contributes nothing to magic defence was updated to the approved 30% contribution.
