# Titan physical slam: single-tile spike

User requirements: preserve the approved slam. One reusable stone-spike animation per affected 32-world-pixel cell; ten distinct scattered cells per attack, including the player's captured cell. Physical warning color is red. Spike retracts immediately after reaching its peak; no lingering hazard. This task produces candidate artwork, a reusable independently sampled effect and a real-map preview, not boss damage/balance or a production encounter placement.

## Asset contract and approach

Generate one complete pointed gray stone spike using PixelLab, matching the approved Titan's low top-down perspective, upper-left lighting and crisp warm stone shading. Native working canvas 48x64, density one world pixel per texel; anchor (24,52), affected ground cell 32x32 centered at the anchor. Keep spike ground base and red cracks inside that cell. Height can extend upward. Use transparent pixels outside the effect; no floor tile or character baked into it. Reuse the approved Titan source solely as a style reference. The original planned anchor y56 was moved to52 to leave clean transparent margins around the crack stroke; source and sprite offset move together, preserving actual world contact and size.

Generate/repair the spike, then create a short consistent emergence/retraction sequence, plus red warning cracks. Keep warning separable so the engine controls its duration. Prefer source PNG frames and a portable Godot effect over a flattened ten-spike animation. Do not rotate tall sprites to vary instances or invent different spike assets.

## Steps

1. Save generation provenance and untouched output; inspect native/full nearest-size sprite. Select exactly one complete spike.
2. Produce transparent warning/eruption/retraction frames and timing manifest. Eruption starts at approved slam contact (1020ms in the review); no peak dwell. Preserve anchor and source density. Build a reusable Godot scene with externally controlled time and no collision/damage authority.
3. Reuse actual Golem Kingdom content and peasant sprite in a dedicated development review. Render one instance at 1x/4x and ten independent instances at scattered grid centers. Query actual floor/wall clearance and exact escape routes in the review. No edits to map or actor catalogs. Passive-prop worldbuilding does not support animated effects; run it against the actual animated scene to record that limitation, never disguise an atlas as a passive prop.
4. Verify alpha/native frame size/anchor, no outside-cell ground footprint, immediate retraction, ten unique cells with captured target included, source/slam unchanged, Godot effect sampling and native 4x screenshots. Save evidence outside Git. User visual approval and production installation remain pending independently.
5. Commit exact task files on codex/golem-titan-bound-animations with an isolated index, preserve the active checkout/index/unrelated work, verify origin, push explicitly. Present actual animated map preview for artwork review.

## Review focus

Check red cracks stay visible against warm stone, spike reads as stone rather than fire, no detached terrain square, spike slides through floor rather than shrinking, no full-height hold, no hidden retargeting or random selection in artwork. All ten instances share one frame set. Do not claim production placement/worldbuilding validation for a development VFX review.
