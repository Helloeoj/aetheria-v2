# Item visuals

Batch 001 contains ten bronze items awaiting art approval. Their runtime assets
are installed for review under `Assets/Items/batch_001/`. The original equipped
layers, eight facings and attachment rules remain the canonical artwork.

`data/item_visuals.json` maps exact catalog names to separate inventory and ground
PNGs, the existing equipped scene and world scale. `ItemVisualLibrary` loads this
registry. Extend `items` for future batches; preserve previously approved entries.
Keep generation IDs and source provenance in each batch's manifest.

Inventory icons use a 64×64 transparent canvas with the visible object's longest
dimension equal to 40 pixels. Preserve aspect ratio. The journal draws these in
equal 48×48 widgets. Ground sprites have independent object-appropriate dimensions
and scale. Every state must have the same construction, materials and details.

On monster death, items with ground art become `GroundItemDrop` nodes. Their
quantity is awarded only when collected. Press F within two tiles or click a
nearby drop. Gold and items without ground art keep their existing award behavior.

Validation: `scripts/dev_tools/item_visuals_smoke.gd` exercises the real monster
death handler, pickup range, quantities, double collection protection, resource
dimensions, unchanged equipped scene references and journal icons. Batch 001
passes 137 checks. Actual captures and all 80 equipped views are saved under
`C:/Users/Riptide/Documents/ChatGPT/Aetheria/work/item-visuals/batch-001/`.

Complete and review only ten catalog items at a time. Wait for user approval
before producing the next batch. An installed review candidate is not approval.

## Raw fish batch

`Assets/Items/fish_001/` contains ten PixelLab Pixen fish icons based on the
user-approved descriptions: Reedkip, Marlo, Bracken, Kessa, Veilfin, Lumara,
Vesper, Moonfin, Velora and Sunfish. The registry maps only their exact
`Raw <species>` item names. Fishing Pale, backpack and scaled ground drops all
resolve the same inventory-state image; cooked and burnt catalog states remain
separate. The artwork is installed as a review candidate.

Original source sheets, exact prompts, reviewed component selections, and export
bounds are preserved in `art_sources/fish_001/`. The importer supports explicit
alpha-component selection because generated sheets do not always obey cell
boundaries. It rejects clipped selected silhouettes before writing any final
sprites, then exports centered transparent 64x64 icons with 40px visible bounds.

`scenes/dev_tools/fish_sprite_smoke.tscn` verifies all ten PNGs, distinct pixels,
alpha, dimensions, exact pale/backpack/ground texture identity, individual fish
slots, raw/cooked/burnt separation, and drop/pickup. Add `-- --capture=<directory>`
for a labelled roster and real fishing/backpack previews. The existing bronze
visual test scopes itself to `batch_001`, preserving its equipment validation.
