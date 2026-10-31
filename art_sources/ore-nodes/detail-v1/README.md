# Ore clarity revision

Twenty 128×128 transparent full/depleted sprites for the existing ten ore types.
These are the current canonical scene textures. Original96×96 sources in the
parent directory remain immutable palette/design provenance.

The scene root remains scale 1. Visual scale 0.75, native anchor (64,96), world
anchor (48,72),96×96 world canvas and both original collision bases preserve
existing placements. Full/depleted states share the same binary alpha.
Every depleted image is identical. Full variants change only the509 pixels
in `vein-mask.png`; all other host RGB is identical.

Two built-in imagegen edits produced the saved high-resolution host and vein
template. No PixelLab calls were used for this revision. `generation-prompts.json`
contains exact prompts, reference paths and operation IDs. References, raw
outputs, registration and palettes are retained. The deterministic builder
registers the two complete boulders onto the original silhouette, rasterizes
once at 128px and applies the original mineral palettes without dithering.

`python tools/build_ore_clarity.py --output <new-empty-folder>` reproduces all
23 accepted PNGs (20 states, host, alpha and mineral mask) byte-for-byte with the
recorded Pillow/NumPy versions. It does not generate, overwrite canonical art
or install assets. `tools/install_ore_clarity.py` performs validated installation.

Approval: the user approved the fine-linework environment reference and asked
for matching ore clarity. Final ore artwork is presented separately for review;
automatic tests do not constitute human approval. Installation: all20 canonical
scenes point to `Assets/MapTiles/OreNodes/Detail128/`. Real 4x Godot renders with
the unchanged player and the actual29 ore placements were inspected. No mining
rules, world placements, collision shapes or camera settings changed.
