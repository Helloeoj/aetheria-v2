# Starforged acquisition implementation

Approved scope: `docs/mining/starforged-audit.md` and the user's drop-exclusive requirements. Work in the active project; no new items, sources, rates, combat changes or save schema changes.

1. **Regression first:** add `godot_client/scripts/dev_tools/starforged_acquisition_smoke.gd` and matching scene. Cover all canonical Starforged records, removed recipes, injected conversion attempts, authority, legacy saves, loot policy and Mining rejection. Update contradictory Smithing/acquisition expectations; demonstrate failures before production edits.
2. **Retire safely:** retain IDs 256/257 with `legacy_placeholder`, no crafting/generic loot and no source policy. Keep existing stacks inert and round-trippable; no confiscation, remapping or backend migration. Existing inventory transfers do not manufacture items.
3. **Close production routes:** remove all 17 Starforged recipes; mark remaining canonical Starforged items non-craftable/drop-only. Shared acquisition/crafting validation rejects Starforged outputs and retired inputs, including aliases. No salvage subsystem exists; future conversions must use the same manufacturing guard.
4. **Preserve presentation:** filter Starforged from Smithing selection without removing equipment icon classification. Reject Starforged F6 grants in both views, retaining the existing interface and catalog inspection. Leave Celestial aliases untouched.
5. **Validate and deliver:** run focused Godot regressions, existing crafting/Smithing/equipment/persistence/Mining tests, editor import and startup. Review, commit only task files and push `codex/starforged-acquisition` to the verified v2 origin.

Drop decision: preserve equipment and component/ammunition eligibility and all existing loot tables unchanged. Actual tier-7 gear supply and rare pickaxe identity/source/rates remain unapproved/unimplemented; do not invent them. Ore/Ingot have no allowed new source.
