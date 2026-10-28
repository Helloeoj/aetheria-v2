# Sentinel live updates implementation plan

**Goal:** Add a manual Sentinel action to publish and activate the existing live beta release, with accurate status and progress.

**Design:** Add a Live server tab without changing existing Sentinel panels. A read-only preview shows the configured target, installed/running release and saved local source, including uncommitted files. Explicit confirmation starts the existing `server.ps1 build` beta workflow. That workflow builds/audits a matching client/server pair, publishes through the capped uploader, gracefully saves/stops the world, backs up data and activates the release. Completion requires observing the selected release and actual running process; exit0 alone is insufficient. No automatic deployment, new hosting, credential collection, AI job or game-art generation.

**Architecture:** `sentinel_deploy.py` owns sanitized preview/status and the existing command's worker process. `sentinel_deploy_panel.py` owns Tk controls, a bounded event queue, confirmation, progress and close protection. Worker threads never touch Tk widgets. `sentinel.py` adds one tab and a close hook. Server credentials and receipts remain outside Git.

**Constraints:** Preserve the dirty shared checkout and existing panels/features. Do not perform a real publish/restart just to test this feature. The saved local project is the build source; never silently checkout/pull or imply only a Git commit is deployed. Failed saves/builds/uploads are failures, with no force-kill or automatic retry.

- [x] Backend: preflight, duplicate rejection, command wiring, failed exit and observed-release verification; existing release process reused. Review regression rejects a conflicting account-data override before launch.
- [x] Interface: real Tk construction, confirmation/decline, worker responsiveness, failure/success reporting, duplicate protection and closing during an update; existing tabs retained.
- [x] Verify: 79 controller/Tk/Sentinel/beta regression tests and 22 standalone real-process Sentinel checks passed; Python compilation passed. Actual Windows panel inspected. Read-only installed release is beta-20261023.1: matching pair and ready world process verified, public ingress not verified. No real publication/restart performed. Scoped changes prepared on `codex/sentinel-live-updates`, preserving the shared checkout/index and unrelated edits.

Context7: official CPython queue/Tk event-loop documentation consulted for main-thread UI updates. User standing instructions waive routine design/implementation approval gates; explicit deployment confirmation remains a product action for the operator.
