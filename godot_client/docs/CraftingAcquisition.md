# Crafting catalog and acquisition

## Implemented catalog

The standard metal ladder is Bronze, Iron, Steel, Blacksteel, Mithril,
Adamantite, Starforged. Existing Runite equipment IDs and numerical stats are
preserved under Starforged display names. Historical Runite names still resolve.

Cloth capes are Homespun, Woven, Runic, Enchanted, Astral, Empyrean and Celestial.
Every standard cape uses `material: Cloth` and `crafting_skill: tailoring`.
The former metal-cape names remain aliases; their existing defensive values
are preserved.

Canonical staffs are Apprentice, Adept, Runic, Enchanted, Astral, Empyrean and
Celestial Magic Staff. Their original staff IDs, cadence and combat values are
preserved. Existing wand records retain their IDs and original stats for
compatibility under the name `[mage prefix] Legacy Magic Staff`, with
`legacy_placeholder: true`, and cannot generate as loot. Their historical name
aliases resolve to the same preserved item ID, so opening a saved inventory
cannot change its damage, accuracy, cadence, projectile speed or handedness.
Explicit compatibility metadata retains the old projectile profile and one-hand
shield support while classifying the item as a staff. Item browsers and tier
catalogs omit those retired records. Each canonical staff tier also has Fire,
Ice, Lightning and Hurricane variants with the same base numerical stats and
an `orb_element` identifier. Those variants do not enter generic loot.

The catalog now defines all seven metal ores, ingots, arrowheads, arrows and
bolts; all seven approved leather and cloth materials; the starter hide and
creature-derived higher hides/scales/skin; Animal Sinew; tier-1 Logs and Wooden
Staff Body; plain and empowered Magic Orbs; and four elemental sigils. No tree
species, mining deposits, new bosses or artwork are added. Existing Ripped
Cloth remains its own item; it has not silently become a new cloth tier.

Tanned Leather Coif, Tunic and Chaps are usable starter definitions. They copy
the existing Bronze Helmet, Platebody and Platelegs defensive values exactly
as a provisional equal-tier baseline. No existing equipment stats changed.
Higher leather armor and robes still require a reviewed balance specification;
material definitions do not imply those full equipment sets are implemented.

Rings and necklaces have `craftable: false` and `drop_only: true`. Plain Magic
Orb and elemental sigils are also explicitly not craftable. Orb empowerment
is the permanent conversion of one existing orb using one existing sigil.

## Runtime source enforcement

`scripts/acquisition_rules.gd` reads `data/acquisition.json` and exposes static
`can_drop(item, monster)` and `can_purchase(item)` predicates. These are source
eligibility checks, not drop rolls. `LootSystem` calls the drop predicate in
both explicit guaranteed/common/rare tables and generic candidate pools.
An explicit table cannot bypass source restrictions by naming a protected item.

- Starforged crafting materials/components: Golem Titan only.
- Aetherwyrm Leather: Aetherwyrm only; its encounter is future content.
- Celestial Cloth: blocked until its boss source is chosen.
- Any new tier-7 Crafting or Ammunition record without a policy: blocked.
- Plain Magic Orb: known cultist-family creatures only.
- Elemental sigils: named boss eligibility only; individual assignments and
  rare-drop odds remain pending. No existing sigil drop rolls are introduced.
- Animal Sinew: known wolf, bat or spider families only. Humans, humanoids,
  trolls, goblins, kobolds and harpies cannot supply it, even when a caller
  supplies a misleading family or `is_boss` flag.
- Wolf, direwolf, troll, dragon and demon hides/leathers retain their creature
  source restrictions. Future dragon/demon families require real templates.
- Beginner, Apprentice, Pro and Master Rod: bait-store purchase eligibility,
  excluded from monster drops.
- Demon Rod: Demon Overlord only, no shop purchase. Encounter and rare-drop
  odds remain pending.
- All three fishing-bait grades: shop and monster-drop eligibility.

Boss eligibility uses the exact configured names Golem Titan, Aetherwyrm and
Demon Overlord. A generic `is_boss` flag does not qualify an unrelated monster.
The existing Golem Titan is tier 5; its explicit Starforged source eligibility
does not depend on pretending that its current tier is 7.

Pending boss/cultist sources have `generic_loot: false` and `supply_pending`
metadata. Their future tables can author reviewed probabilities without adding
a new acquisition system. No deferred cultist, sigil, highest-material or Demon
Rod odds have been invented. Lower crafting components can use existing generic
loot rolls at appropriate tiers. Finished equipment is separate from crafting
materials; this change does not globally rewrite existing artifact or equipment
loot balance.

Future gathering and shop implementations must preserve the top-material gate.
In particular, ore deposits cannot become a bypass for Starforged Ore.

## Validation

Run the normal-autoload smoke scene:

```text
Godot --headless --path godot_client res://scenes/dev_tools/catalog_acquisition_smoke.tscn
```

It verifies catalog uniqueness, aliases and retired-ID preservation, staff
variants without stat changes, cape ownership, source and purchase policies,
humanoid sinew rejection, and real explicit/generic loot enforcement. It also
injects prohibited guaranteed drops to verify the explicit path fails closed.
