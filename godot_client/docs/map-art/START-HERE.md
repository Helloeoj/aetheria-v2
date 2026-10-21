# Aetheria map art workflow

Use this entry point for map creation, expansion, image edits and reusable environment assets.
Goal: retain the current visual quality while reducing repeated generation, extraction and project discovery.

## Read only what the task needs

1. Read [ART-SPEC.md](ART-SPEC.md), then the relevant row of [ASSET-INDEX.md](ASSET-INDEX.md).
2. Choose **reuse**, **local repair**, or **missing asset**. Reuse is the default.
3. Record the small task brief from [TASK-TEMPLATES.md](TASK-TEMPLATES.md).
4. Follow the matching [RECIPE](RECIPES.md). Read a detailed project document or script only when that recipe needs it.

Do not inventory the entire repository, reopen historical reports, dump map-cell manifests, or reread every art document on each task. Parse large JSON and return only selected entries. Existing assets and their metadata are the first place to look.

## Working defaults

- Environment only: no characters, creatures, NPCs, enemies, golems, animals or character sprites baked into artwork.
- Preserve the current art direction, geography and gameplay scale unless the requested change includes them.
- Assemble maps from terrain and complete object assets. Generate only missing pieces.
- For a visual repair, edit a bounded crop with neighboring context, then install only the allowed region/layers. A prompt alone does not guarantee preservation: compare the result to the baseline.
- Keep source art, export metadata, review status and installation status separate. A generated or installed candidate is not automatically visually approved.
- Follow the user's existing authorization. A preview-only request remains preview-only; this workflow adds no new approval gate.

The existing PixelLab world library remains **planned, not generated**. Its saved generation hold is not resumed by setting up this workflow. Reuse the installed brushes, objects and clean trees meanwhile.

## Where the work lives

Game-relative paths below resolve from the repository root; `res://` resolves from `godot_client/`.
The separate supporting Aetheria workspace holds `work/map-planning/`: previews, references, extraction tools, packaging and historical evidence. Its `WORKFLOW.md` points here.

For ongoing work, keep one small task record with selected asset paths, exact prompt/settings if generation was needed, changed rectangle, review result and next action. Update that record instead of producing another full plan.

Suggested request: **“Use Aetheria's saved map-art workflow. Repair [area/detail], preserve its layout, reuse existing assets, and show the local before/after.”**

No token-saving percentage has been measured. The savings target is fewer repository reads, fewer generation attempts, smaller edit regions and reusable imports.
