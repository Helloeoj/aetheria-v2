# Repeatable export and import recipes

Choose one recipe. Normal map editing does not require running source builders. Follow the user's current preview/install scope; these instructions do not authorize additional areas or paid batches.

## 1. Reuse and paint — default, no generation

1. Open `res://scenes/ValtheirisWorldContent.tscn` in the active Godot project.
2. Select the existing terrain or object layer. Pick the indexed brush/scene tile from its existing `World*.tres` palette. Paint at native scale; retain source IDs.
3. For objects, reuse the scene tile so its foot anchor and collision travel with it. Shared object-scene edits affect every instance; create a distinct variant when only one placement should change.
4. Save. Capture the changed area at gameplay zoom and close-up; inspect edges and depth sorting. If collision or walkability changed, validate those paths too.

Do not rerun asset extraction, wilderness builders or the world merger after ordinary painting.

## 2. Local terrain repair

1. Fill the local brief. Capture the current target crop and a context border. Keep a baseline of affected PNGs, the scene and TileSets; preserve editor work before external resource writes.
2. Reuse matching brush pixels where possible. If generation is necessary, supply the target plus at most the necessary saved references; request only the local change.
3. Save the untouched generated original, exact prompt/settings, dimensions and any service IDs. Assemble the candidate using explicit masks; copy original pixels outside the mask. Verify the expected crop/world mapping rather than assuming the generator returned the requested size.
4. Export aligned RGBA PNGs at the intended native density. Terrain backing must cover ground beneath objects. Props stay separate; do not infer collision from image colors.
5. Review before/after at native/gameplay zoom plus close-up. Inspect the whole crop, seams, silhouette edges and unchanged geometry. Record the review status.

For the existing overworld review installer, origins and positive sizes must be multiples of 32 world pixels. One PNG pixel equals one world pixel in this route. Allowed layers are **Grass**, **PathsAndQuays**, **GroundDetails** only. Water, objects and dungeon art use their own resources; this installer cannot change them.

The registry is `res://Assets/MapTiles/ReviewSections/sections.json`. Each entry has `id`, integer `origin`/`size`, and `layers` entries containing `name` and `texture`; PNGs live beneath `res://Assets/MapTiles/ReviewSections/` and match the exact size. Do not overlap sections on the same layer. The installer may clear transparent cells on those layers inside the registered rectangle: inspect alpha as well as visible RGB.

Import changed PNGs with the installed Godot executable, from the game repository root:

```powershell
& $GodotExe --headless --editor --path godot_client --quit
```

`$GodotExe` means the installed Godot 4.5.1 executable, not a download or upgrade. Check process status and error output before loading textures.

`godot_client/tools/apply_review_sections.gd` is a **RefCounted helper**, not a standalone command. Its `ReviewSectionInstaller.apply(world, registry_path)` works on an off-tree world instance; the caller must save returned modified TileSets and pack/save the scene. Use the existing D4D5 wrapper only for deliberately reapplying that reviewed section: it applies the full default registry and writes its fixed D4D5 report. It is not a generic new-zone installer.

For another rectangle, adapt a caller deliberately within the requested task, with region preservation checks. Never run the world merger merely to install one patch. Compare cells outside the allowed rectangle/layers, object placements, collision and anchors before/after. Render the saved runtime scene after import; an image composite alone does not verify installation.

## 3. New standalone terrain/prop kit

Check the index first. Generate only missing families; match one sample before expanding. Keep original PNGs, native dimensions, prompts, settings and service IDs with the kit. Props need true transparency and manually reviewed root anchors. Terrain needs connectivity metadata and assembled seam tests.

For PixelLab terrain, retain exact base-tile IDs when chaining families, and export actual service tile bounds/corner or edge metadata. Corner-based Wang and N/E/S/W path rules are different systems. Do not infer topology from sheet order. Road generators may include opaque grass; do not color-key it away.

Existing packaging lives in the supporting workspace:

```powershell
# Run in work/map-planning/pixellab-world-library after saving downloads.
# NodeExe is the installed/bundled Node executable; see workspace dependencies.
& $NodeExe ./build_library.cjs ./downloads-manifest.json
```

Use `downloads-manifest.example.json` for the schema. Replace every example value with real metadata. The builder supports **trees, rocks and roads**, crops atlas regions at native size and writes originals, metadata, inspections, contact sheets and gallery. It writes into its own script folder; preserve an earlier completed output before rebuilding there. It does not import anything into Godot.

Review the gallery, specify actual foot anchors, then write the kit README with topology, counts and limits. Package with:

```powershell
./package_library.ps1
```

It refuses to overwrite its existing ZIP. Rename/archive that ZIP before a deliberately new version. Retain source art and metadata with every delivered kit. Packaging success is not proof of seamless terrain, useful collision, or visual approval.

## 4. Import a new asset family into Godot

1. Keep source files under `art_sources/<kit-id>/`; runtime PNGs belong in an appropriate `godot_client/Assets/` family. Preserve canvas/alpha and avoid resampling existing sprites. Use nearest filtering, lossless texture compression, and no mipmaps for the established crisp art unless the area has an explicit exception.
2. Import PNGs before constructing resources. For overworld terrain, append new sources to the existing relevant TileSet with 32-pixel regions; preserve existing IDs and painted cells. New Wang/path terrain rules require explicit metadata mapping and seam tests; existing patch brushes do not become autotiles automatically.
3. For props, create a reusable scene with artwork, a reviewed foot anchor, depth sorting and appropriate authored base collision; register it as a scene tile. Anchor metadata alone does not create physics.
4. Place only within the requested area, save, and compare protected geometry/cells. Check walkable routes, water, bridge decks, and behind/in-front object sorting as relevant. Update the asset index and task record.

For the dungeon, follow its [asset guide](../../Assets/Maps/GolemKingdom/README.md), preserving Detail4x transforms and materials. Its existing regression command, from the game repository root, is:

```powershell
& $GodotExe --headless --path godot_client --script res://tools/golem_map_smoke.gd
```

Require successful checks and review stderr, including shader errors. This recipe setup has not run that gameplay test because no game art or code was changed.

## Full source rebuild — exceptional

Rebuild only when the task explicitly requires regenerating source conversion and after preserving manual edits. Consult [MapEditing.md](../MapEditing.md) for asset build → Godot texture import → wilderness scene build → world merge ordering. These tools can overwrite painted cells and generated resources. The older dungeon converter also does not preserve the current restored bindings automatically.
