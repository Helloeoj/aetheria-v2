# Titan Skeletal Idle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Give the Titan a real articulated skeleton and fluid subtle idle while preserving the user-approved ground slam.

**Architecture:** One continuous textured mesh is weighted to native Godot Skeleton2D/Bone2D chains. The source texture remains whole; spine, clavicle, elbow, wrist and neck controls move independently. Bake native-resolution review frames from the actual rig, then review those frames with the unchanged Golem Kingdom content and real player.

**Tech Stack:** Godot 4.5.1, native lossless PNG, existing graphical review harness.

**Spec:** User feedback in this task: approved fluid slam; rejected six rigid image sections; subtle chest/arm movement; anchored legs and bindings; actual skeleton required.

## Global Constraints

- Native 256Ã—256, anchor [128,240], one world pixel per source pixel, nearest filtering.
- Preserve the complete source identity and exact neutral pose; do not repaint or slice it into moving bitmap sections.
- Keep pelvis, legs, feet, magical bindings and ground anchors fixed.
- Preserve the approved slam byte-for-byte; no runtime catalog, gameplay or map placement changes.
- Routine implementation, verification and task-branch commit/push are already authorized.

## Review Focus

- Bone hierarchy and normalized local skin weights must produce genuine independent elbow/wrist/spine motion.
- Native neutral rendering must equal the source; full-cycle pose must return exactly.
- Fixed controls and native lower-body pixels must remain unchanged, including restraints beside the fists.
- Joint deformation must keep complete hands, armor volumes and connected silhouettes without exposed seams.
- Actual 4Ã— map/player captures must show crisp artwork and ground contact; artwork approval remains separate.

### Task 1: Native skeleton and weighted mesh

**Files:** new `godot_client/scripts/dev_tools/golem_titan_skeleton_rig.gd` and UID; complete source texture under `godot_client/Assets/Characters/GolemTitanBoundCandidate/`.

**Interfaces:** source-top-left origin; `sample_at_seconds(t)`, `set_debug_skeleton(enabled)`; 2.4-second periodic motion.

- [x] Build actual Bone2D chains with fixed pelvis/legs and independently articulated upper body.
- [x] Weight a continuous UV mesh locally across joints; retain full original source bitmap.
- [x] Check script parsing, bone hierarchy, nontrivial independent controls, normalized weights and exact neutral/full-cycle poses.

### Task 2: Bake and review the actual rig

**Files:** new `godot_client/scripts/dev_tools/golem_titan_skeleton_bake.gd` and UID; selected V2 idle frames/provenance and README. Existing map review tool remains unchanged.

- [x] Render 48 native samples at 50ms each plus a separate exact-cycle endpoint and visible skeleton proof.
- [x] Validate native palette/alpha, fixed lower body, complete silhouettes, margins and neutral loop closure.
- [x] Capture all selected poses at real Godot zoom 1 and 4 alongside the unchanged player; inspect joint and armor behavior.
- [x] Verify lossless animated map preview decoding and timings; retain unchanged slam and its approval status.
- [x] Commit only completed task files using an isolated index, preserve the active unrelated branch/work, push the existing Titan task branch and verify the remote hash.
