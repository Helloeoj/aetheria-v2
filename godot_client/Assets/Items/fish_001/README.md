# Raw fish inventory sprites

Ten PixelLab Pixen designs from the user's approved fish descriptions. These
are the caught/raw inventory state, with the same image shared by the Fishing
Pale, backpack, and scaled ground drop. Exact `Raw <species>` item names are
registered in `data/item_visuals.json`.

Each icon has a transparent 64×64 canvas and centered artwork with a 40-pixel
longest side, matching the existing inventory art convention. Original pair
sheets and exact generation prompts are preserved in `art_sources/fish_001/`.
`manifest.json` records species, source jobs and gallery IDs. The source folder's
`source_layout.json` selects the reviewed complete fish by connected outline;
`normalization.json` records source bounds and nearest-neighbor export details.

To reproduce the exports from the repository root:

```powershell
& $env:GODOT --headless --path godot_client --script res://tools/import_fish_sprites.gd -- --source=<absolute path to art_sources/fish_001> --layout=<absolute path to art_sources/fish_001/source_layout.json>
```

Add `--validate-only` to check all ten source cells without writing outputs.
Cooked and burnt items have separate catalog names and keep their own visual
state; this batch does not assign raw fish artwork to them.

The visual designs were approved before generation. The rendered sprite batch
is installed as a review candidate.
