# Development synchronization

The authoritative repository is [Helloeoj/aetheria-v2](https://github.com/Helloeoj/aetheria-v2),
with private visibility and integration branch `main`. Open
`godot_client/project.godot` in the installed Godot **4.5.1** engine. The
`legacy/` tree is reference material, not the active game.

The old `Helloeoj/aetheria-game` repository must remain untouched. Its local
remote is named `legacy-origin`, with pushing disabled. `origin` points to v2.
The initial v2 import retains the existing Git ancestry and adds the actual
current local game, including previously untracked work. No game content is
deleted to make synchronization succeed.

## Required completion of every coding task

1. Inspect `git status --short --branch`, the current branch, and
   `git remote -v`. Fetch `origin` and review divergence before integrating.
   Confirm its push URL is `https://github.com/Helloeoj/aetheria-v2.git`
   (the equivalent SSH URL is also valid). Never use `legacy-origin` for writes.
2. Work on a descriptive `codex/<task-name>` branch. If uncommitted work already
   exists, identify ownership and preserve it; do not reset, clean, stash away
   or include unrelated work without understanding it. Do not switch branches
   in a way that loses local files.
3. Review the diff and new files. Run relevant tests with the installed engine,
   plus an editor import/parse check and main-scene startup check when runtime
   scripts, scenes or assets changed. Check actual output for script errors;
   Godot's exit code alone is insufficient. Retain evidence outside the repo.
4. Stage explicit appropriate paths with `git add -- <paths>`. Review
   `git diff --cached --stat`, `git diff --cached`, and
   `git diff --cached --check`. Inspect for secrets and accidentally staged
   generated files. Keep `.uid` and source-side `.import` files with their assets.
5. Commit the completed, validated change with a descriptive message. Push with
   `git push --set-upstream origin <task-branch>`; never force-push. If rejected
   because the remote advanced, fetch and inspect before safely integrating
   and rerunning relevant tests. Do not overwrite remote work.
6. Create a pull request into `main` when ready for integration. Use ordinary
   merge/review procedures; do not bypass branch protections. Update its title
   and description to explain the final change and validation.
7. Verify `git ls-remote origin refs/heads/<task-branch>` matches the local
   commit. Report validation, any remaining local changes, the commit hash,
   and the GitHub commit or pull request URL.

These steps are standing authorization for Codex to finish completed development
tasks. They are enforced through the repository's `AGENTS.md` instructions.
There is no timer or file watcher that blindly commits unfinished work. Failed
tests, unresolved conflicts, credentials, unrelated changes, or unavailable
GitHub access must be reported honestly while preserving local work.

## Validation commands

Use your installed Python and Godot executables; set `GODOT` to the installed
Godot 4.5.1 executable. The PowerShell ADC launcher can also detect an already
running Godot process. No engine upgrade is needed for synchronization.

```powershell
# From the repository root. Keep generated validation outside this directory.
& $env:GODOT --headless --editor --path godot_client --quit
& $env:GODOT --headless --path godot_client --quit-after 120

# Inventory, cooking, fishing, food and skill regressions.
python tools/test_inventory_items.py --godot $env:GODOT
python tools/test_cooking.py --godot $env:GODOT

# Crafting catalog and real crafting transactions.
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/catalog_acquisition_smoke.tscn
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/crafting_service_smoke.gd
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/crafting_ui_smoke.tscn

# Combat, sprites and world interactions; add tests relevant to the change.
& $env:GODOT --headless --path godot_client res://scenes/dev_tools/bronze_combat_smoke.tscn
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/sprite_integration_smoke.gd
& $env:GODOT --headless --path godot_client --script res://scripts/dev_tools/world_interaction_smoke.gd
& $env:GODOT --headless --path godot_client --script res://tools/golem_map_smoke.gd

# Diagnostic integration changes: isolated synthetic incidents are expected.
./tools/adc.ps1 test
```

Tests may deliberately write reports or screenshots. Inspect a test before
running it, isolate diagnostic output, and review `git status` afterward. Do not
commit generated evidence. For reported errors, use the ADC preparation and
compact-report investigation process in `AGENTS.md` before changing code.

## What belongs in Git

Include scripts, scenes, catalogs, resources, maps, item/character sprites,
audio, original art, required configurations, source-side import settings and
Godot `.uid` files. `.gitignore` excludes `.godot/`, Python caches and virtual
environments, Node dependencies, exports/build output, credentials, temporary
files, logs and regenerated art-validation reports. Ignoring a file never
deletes its local copy.

Inspect asset sizes before pushing. If a future required asset exceeds GitHub's
file limit, configure Git LFS appropriately or discuss a suitable asset store;
never delete required content or silently replace it with an unavailable link.
