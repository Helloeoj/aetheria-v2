# Completed smithing items in both menus

Implement directly in the active project, preserving unrelated local work.
The user requested the existing furnace/anvil and F6 menus, explicitly excluding
bows/crossbows, capes, staffs/wands and drop-only jewelry.

## Scope and decisions

- Seven existing metal tiers, Bronze through Starforged. Add Coal for the user's
  alloy correction. Preserve existing IDs/stats, artifact rules, gathering scope,
  login/saves and online authority.
- Enable each tier's ten existing metal weapons/armor/shields with the same
  per-category ingot quantities as Bronze. Smelting consumes one corresponding
  ore per ingot except Steel: 1 Iron Ore + 1 Coal -> 1 Steel Ingot.
  Keep the historical Steel Ore record for save compatibility, outside the new
  Smithing list.
- Preserve previously enabled Bronze ammo/Fletching recipes. Other unfinished
  recipes remain pending; furnace/anvil display completed routes only.
- Add a pure SmithingCatalog classifier shared by F6 and placeholder lookup.
- F6 opens a Smithing view with 84 items, icons, clickable rows and quantity.
  Keep All Items, typed IDs, Enter, PageUp/PageDown and normal equip requirements.
  Never permit developer grants online or overflow a stack.
- Crafting buttons reuse authored icons or generic metal gear placeholders.
- Keep these two existing interfaces above the permanent HUD with a scaled
  canvas layer; preserve the HUD and its behavior after the menus close.

## Execution

1. Write and run failing catalog/menu regression coverage.
2. Implement classifier, scoped recipe data, placeholder fallback and SVGs.
3. Extend the existing F6/crafting UI without replacing either interface.
4. Verify recipes, actual input, quantity/equip behavior, exclusions, overflow,
   server transactions, existing suites, editor import, startup and rendered UI.
5. Review, stage explicit files, commit/push codex/smithing-catalog-menus and
   create a scoped PR on its existing Bronze-recipe parent branch.

Timing/minigame migration and new XP progression are outside this menu change;
the active crafting authority and character persistence remain intact.

## Validation completed

- New regression: 809 headless checks and 812 rendered checks; inspected all
  three menu captures. Includes actual row/button clicks, resize, scrolling,
  keyboard paging, missing Coal, server replay rejection and safe equipment
  replacement at inventory limits.
- Existing regressions: 243 Bronze, 1202 crafting service, 17 crafting UI,
  1064 acquisition/catalog and 122 inventory checks; all passed.
- All 13 networking suites and 12 cooking/fishing suites passed. Rechecked
  development controls and original online minigames after the modal layer fix.
- Editor import/parse and main login-scene startup passed. Independent review
  found an equipment-return overflow case; added failing reproduction tests,
  fixed the grant preflight and reverified. No remaining review blockers.
- Data comparison confirmed only 66 formerly pending smithing routes changed;
  all other recipes, equipment definitions/stats and existing IDs were retained.
  Coal is appended as ID 329; only historical Steel Ore loot/description changed.

This is local and authoritative-region validation, not a live account-server
end-to-end test. Generic gear art remains temporary.
