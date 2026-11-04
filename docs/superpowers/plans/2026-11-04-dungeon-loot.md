# Dungeon loot implementation plan and contract

Goal: let beta testers collect complete armor sets through Adamantite in
Valtherian Mines, including the four retained sprite-backed skeleton types.

Architecture: one dungeon-specific explicit loot table selected by metadata
on the shared offline/server population. Other areas retain their existing loot.
Existing tier gold and death, ground-drop, pickup and save paths remain in use.

The user's final rates apply across all dungeon mobs: Bronze 15%, Iron 12%,
Steel 12%, Blacksteel 8%, Mithril 10%, Adamantite 7%. One mutually exclusive
armor roll per kill; on top enemies the remaining 36% yields no armor. Each tier splits its weight
equally among helmet, platebody, platelegs, square shield and matching cape.
Rates apply only to eligible tiers, without normalization. Scouts cap at Bronze;
Workers/Footsoldiers at Iron; Warriors/Knights at Steel; Shamans/Acolytes at
Mithril; Chieftains/Captains at Adamantite. This follows the user clarification
to scale tiers by mob difficulty. Higher-tier weights yield nothing on weaker mobs.
No weapon/material bonus rolls inflate these armor odds. No new items, artwork,
placements, combat stats or equipment requirements. Tier-six cape is Empyrean.

Alternatives considered: per-skeleton tables would miss the user's subsequent
all-mob instruction; a global override would change unrelated areas.

- [x] Reproduce missing loot with a failing real Godot regression.
- [x] Add shared data, dungeon metadata selection and remove skeleton suppression.
- [x] Verify exact weights and seeded real drops for every dungeon template;
      run the actual mine population offline/server smoke, import and startup.
- [x] Review scoped diff; author self-review, no subagents by user instruction.

Delivery: commit and push only the explicit task files.

Evidence: 45,000 seeded kills across nine templates; all eligible pieces observed,
no ineligible armor; mine population smoke passes offline and server profile/gold
checks; Godot editor import and main-scene startup have no script errors.

Review focus: full five-slot armor coverage, per-kill rather than per-piece odds,
both population authorities, no changes to outside-dungeon drops, and no
suppression of skeleton gold. No subagents per user instruction.
