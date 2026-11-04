# Valtherian clarity and ore library implementation plan

**Goal:** Install the user's approved high-resolution linework treatment across the existing Valtherian Mines and restore all ten canonical ore full/depleted props to matching clarity.

**Approval:** User approved `linework-candidate-mine-palette64-4x.png` and explicitly requested equally clear ore nodes. Earlier soft/pixel-enlargement candidates are rejected. The user's 2026-10-29 instruction permits built-in imagegen; it supersedes older PixelLab-only wording. Do not spend additional PixelLab credits.

**Architecture:** Restore overlapping regions of the existing map, preserve world registration6144×3328, stitch with reviewed joins, rebuild matching foreground masks, and use the mine-specific crisp palette. Generate a sharp shared depleted host rock and a vein template, then derive the existing mineral colours without changing the shared host. Ore native128×128 at visual scale0.75 preserves the96×96world canvas, world anchor(48,72), two base colliders and default root scale1. Retain originals and provenance.

## Non-negotiables

- Keep the approved rooms, corridors, paths, exits, camera and every one of the29 ore root/approach transforms. No gameplay, population, progression or mining-system changes.
- No generic wall/floor kit, procedural replacement map or geometry redesign. Environment images contain no actors/creatures/ore nodes; ores remain individual props.
- Character sampling0.75world pixels/texel is the reference; file dimensions alone do not certify effective clarity. Inspect actual4× renders with the unchanged character.
- Shared host silhouette/foot anchor and depleted alignment remain consistent across Copper, Tin, Iron, Coal, Silver, Gold, Mithril, Adamantite, Runite and Blackstone.
- Preserve unrelated dirty work and the active checkout. Commit/push only validated task changes to `Helloeoj/aetheria-v2` on a scoped `codex/` ref. No automatic live deployment.

## Tasks

- [x] Cave: bounded high-resolution restoration using original framing plus approved style reference; check a larger restoration region before continuing, cap initial whole-map batch at28imagegen calls, skip redundant dark regions, preserve original source and metadata. Rebuild foreground pixels from the same final master and bind the visual-only update without touching collisions/placements.
- [x] Ores: restore shared host/vein artwork, preserve mineral colours and whole transparent silhouettes, register at128native/.75visual and the existing world anchor. Update twenty canonical scenes and native-art metadata/contracts without changing collider polygons or placements. Review light/dark/ground and full/depleted pairs.
- [x] Integration: review all joins and wall/ore silhouettes, actual worldbuilding contract, physics/routes/travel and full ore-library regressions. Compare real4× wall/ore/player and ordinary zoom captures. Keep machine checks, visual approval and installed status distinct. Fix failures before final commit/push.

## Work ownership

Map-restoration helper owns new detail map assets, map-only authoring/build helpers and visual bindings in `ValtherianMinesContent.tscn`. It must not edit ore assets/scenes, layout/marker JSON or shared documentation. Root owns ore art/scenes/native metadata, final contracts/layout metadata, documentation and scoped Git synchronization. Coordinate before final shared-scene verification.

## Review focus

Native sampling with coarse baked art; colour/lighting drift at region joins; generated contours drifting into authored clear floor; foreground atlas pixels differing from the backdrop; full/depleted or mineral variants moving the shared host; raw transparent edges with halos/fragments; stale imports; unrelated checkout changes entering the commit.

## Verification recorded 2026-10-31

Installed locally: restored map and all twenty canonical ore states. All29roots,
approaches, floor/collision/routes and travel remain unchanged. Reviewed all29
actual4× placements, joins, source light/dark views and full/depleted player
comparisons. Automatic evidence:21focused Python tests,1176ore-library checks,
2081actual physics checks, actual worldbuilding contract and154travel checks.
Worldbuilding regression suites pass after updating native-density expectations
and using approximate equality for a transformed fractional-pixel anchor.
Source/import identity and foreground/character comparisons remain recorded
separately. User approved the clarity direction; final renders are presented for
human review without relabelling automatic checks as artwork approval.
No live deployment. Scoped Git synchronization is the final completion step.
