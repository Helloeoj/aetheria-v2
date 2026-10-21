# Current-game repository import — 2026-10-21

The private `Helloeoj/aetheria-v2` repository imports the current local Godot
game, not just the November 2025 Git snapshot. Its project entry point is
`godot_client/project.godot`, using Godot 4.5.1 and
`scenes/EastOutskirtsLayered.tscn`. The existing Git ancestry is retained;
the preceding local HEAD was `6159d92ba4787368655d745fd8f5d44ae71700e5`.
Existing Python moves into `legacy/python/` were already present before this
import. No gameplay restructuring or gameplay fixes are part of the import.

A separate full local backup was made before Git configuration changes. All
14,315 files, including Git metadata, staged work, untracked content and caches,
were verified against the original using SHA-256 hashes. No local game files
were deleted. Generated Godot caches were removed from the Git index only.

## Content and exclusions

The import includes 630 Godot scenes, 120 GDScript sources, 122 `.uid` files,
2,852 source-side import settings and 2,872 PNG assets, together with catalogs,
resources, shaders, source artwork, documentation and development tools.
It includes the current crafting/acquisition, combat, inventory/equipment,
fishing/cooking, eight-skill progression, sprites, outskirts/world, tavern and
Golem Kingdom content.

Excluded local content consists of Godot caches, Python bytecode caches and
four regenerated art reports in `godot_client/data/`:
`fitted_equipment_validation.json`, `limb_shield_validation.json`,
`platebody_seam_validation.json` and `side_fit_candidate_validation.json`.
The tests that produce these reports are retained. `.gitignore` also protects
credentials, local dependencies, temporary files, logs and build/export output.
All exclusions remain on disk and in the pre-import backup.

The largest source asset is 24,224,963 bytes. No asset requires Git LFS for this
import. Credential-pattern scans of the current tracked content and historical
source found no real credentials. The sole current match is deliberately fake
OAuth test data in `tools/test_sentinel_chatgpt.py`. Missing literal resource
paths found by static inspection are intentional negative-test fixtures.

## Validation and known baseline issue

Validation used a separate copy exported from the staged Git index, with no
existing `.godot` cache. The clean editor import and main-scene startup passed.
All 77 Python sources and 37 JSON files parsed successfully.

Fifteen of sixteen validation groups passed. Passing coverage includes crafting
catalog/acquisition (1,062 checks), real crafting transactions (1,199), crafting
UI (17), bronze combat (2,995), goblin combat (70), orb combat (213), equipment
progression (4,435), world interaction (58), camera (40), Golem map integration,
inventory items (121), ten cooking/fishing/food/skill scenes, and diagnostics
(24/24). The initial local runner expected a different success-summary format
for two tests; their explicit PASS outputs were reviewed and accepted. Raw
validation output stays outside the repository.

**Outstanding: `sprite_integration_smoke.gd` fails 7 of 3,836 assertions.**
The identical failures were independently reproduced in the original active
project and the clean staged snapshot. The assertions concern an expected
23-skin catalog versus the current 22 entries, an Iron Longsword attachment,
and attack event/facing expectations in both game scenes. The test did not
report missing catalog textures. No root cause or fix is claimed. This import
preserves the current game as an explicitly documented backup baseline; it is
not a claim that every regression test passes or a release certification.

Four pre-existing whitespace findings in an art prompt, the bundled font
license, recipes catalog and crafting smoke test were preserved without
unrelated reformatting. Existing user diagnostic incidents were not resolved
by this synchronization task.

## Future synchronization

`origin` points to v2. The old repository is retained as `legacy-origin`, with
its local push URL disabled. Its GitHub branches must remain untouched.
`AGENTS.md` requires future completed coding tasks to review and validate their
changes, commit the appropriate files, push a development branch, and report
the commit and GitHub URL. See [DevelopmentSync.md](DevelopmentSync.md).
