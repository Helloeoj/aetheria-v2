# Valtherian Mines native map implementation plan

> **For agentic workers:** Use superpowers:executing-plans for root assembly and scoped parallel workers. User authorization covers routine implementation, validation, commit and push.

**Goal:** Install the approved Valtherian Mines layout using native terrain and reusable props, with exactly the user's 29 marked ore nodes and its own east-facing exterior entrance.

**Architecture:** The approved V3 tile contract remains the spatial authority. Native floor regions from the approved material proof use128px artwork cells at0.25world pixels/source pixel, producing32px physical cells. Complete generated wall props dress an authored continuous cave boundary; canonical ores retain their native sprites, anchors and blocking bases. Generic existing cave travel connects a separate wrapper scene without changing skill rules.

**Tech stack:** Godot4.5.1, Python/Pillow for geometry/marker analysis, built-in imagegen for missing complete wall art; Context7 for Godot API documentation.

**Spec:** `art_sources/valtherian-mines/planning/tile-layout-v3.json`, approved `native-material-proof-v1.json`, and the user's2026-10-28 annotated image/coal correction.

## Global constraints

- Shared gameplay cells32world pixels, origin(0,0), actual actor body24×24; player visual scale and canonical ore scale remain unchanged.
- World6144×3328. Preserve east-to-west route, five branches and declared clear room sizes.
- Exactly29dots: Blackstone12,Coal7,Mithril4,Adamantite2,Iron4. Dots denote visible centers; preserve unconflicted locations, move genuine conflicts minimally, record every correction.
- No actors/ores baked into environment art; no mining/combat mechanics, spawns, drops, smelting or unrelated interfaces changed.
- Native whole assets only; nearest/lossless/no mipmaps. No stretched overview or dirty map cutouts.
- Preserve existing Bracken Mine, wall, trees, portals, character and save state. Do not stage unrelated dirty work.

## Review focus

Marker registration must remove screenshot borders/crops before world mapping. Ore alpha must clear actual wall art and peers, beyond base-only checks. Branches and full-body routes must stay connected. Foreground wall props must sort correctly at4×. Actual portal travel must preserve existing state and work with registered offline/online maps.

## Tasks

- [x] **1. Pin approval and markers.** Preserve the annotated original, register it against V3, extract precise dot centers/colors and record world mapping plus uncertainty. Reuse canonical Coal after the user's correction.
- [x] **2. Native floor and complete wall props.** Create `valtherian_native_floor.gd`; use clean lower proof regions without resizing. Generate a small transparent whole-wall sheet, inspect/export only complete clean silhouettes, save exact prompt/source/native anchors. Validate floor seams and source alpha.
- [x] **3. Author the actual content.** Add `ValtherianMinesContent.tscn` from the approved cell geometry, real void/boundary collision, individual wall/ore instances, exact ore approaches and reserved corridors. Record layout/asset/placement contracts under `Assets/Maps/ValtherianMines/`.
- [x] **4. Separate entrance and travel.** Add a passive reusable east-facing entrance prop in the actual overworld content, an artless generic portal interaction, a new area wrapper and registry entry. Add scoped state-preserving travel checks.
- [x] **5. Verify and synchronize.** Run the actual-scene worldbuilding gate, all-clear-floor/grid and full-alpha clearance checks, portal/grid integration tests and existing relevant regressions. Inspect real1×/4× player renders in every affected room and exterior entrance. Fix failures, record separate automatic/visual/install statuses, commit only owned changes and push to `Helloeoj/aetheria-v2`.

## Execution ledger

2026-10-28: user approved the non-PixelLab native proof and supplied ore dots; grey resolved to Coal. Source-only draft branch at9e670251779e54768c2fd441e93c7fc1fdd80765. Active checkout is shared and dirty; preserve its branch/index and unrelated files. Marker, floor-kit and travel tasks are delegated with disjoint file ownership.

2026-10-28: Tasks1-4 implemented. All29 marked roots retained exactly after independent full-alpha composite checks. Native6wall props plus8whole timber/lantern supports; floor unchanged. Actual worldbuilding12assets/14,337checksPASS; geometry helper8testsPASS; travel154checksPASS after final support. Final fresh GPU/depth review and independent code review pending before synchronization.

Ruling: native modular assembly follows the approved32px cell contract; source overview is never stretched. Derived terrain is more rectilinear and visibly modular than the overview, with native grain preserved. Whole warm supports restore the missing timber/lantern detail without touching ores or routes.

Ruling: exact reserved width stays192/128px. Validator checks full swept polygon against bounds/floor, then uses0.1px per-side numerical interior for physics contact; ordinary24px queries stay unchanged. Focused exact-fit/narrower-floor regressions and all validator selftests pass. Shared texture pixels cache only within each audit by resourceID+path, while every actual sprite remains independently bound and checked.

2026-10-28: Final scene hash3d50ec0db9530358635ca435acd4d239b1f9686dc1c01c31f578183a3c98f4e7. All6319 actual-physics checks and14337 worldbuilding checks pass,12asset types;29exact dots/0nudges;66normalGPUcaptures plus7actualshape overlays inspected. Fresh independent reviewer found no Important/Critical issues; live server/account deployment is outside this local validation. Commit/push receipt is written separately in supporting native-install-sync.json after remote verification.
