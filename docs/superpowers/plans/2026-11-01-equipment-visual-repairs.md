# Equipment visual repairs

Resume scoped repairs in the active game, preserving the rejected patch's
rollback and the approved leg artwork. Existing F7 inspection is the evidence
tool. The user explicitly added capes and all weapons to this task.

1. Trace the shortened face to the source head cut and reproduce with original
   chin-pixel regression. Restore the complete native head outline independently
   of armor without recoloring pixels or changing armor/leg silhouettes.
2. Capture actual Godot poses for bare/armored capes and every registered weapon
   type, including all materials. Inspect individual and adjacent poses; fix
   verified attachment/orientation/occlusion defects at their source.
3. Check upper/lower slot combinations and preserve complete legs/feet. Do not
   add procedural limb filler, stretch armor or reuse rejected whole-body masks.
4. Run relevant regressions, inspect real 1x/4x PNGs and obtain an independent
   visual/code review. Tests and installation do not grant user art approval.
5. Commit only the scoped validated changes and push to Helloeoj/aetheria-v2.

Native art is 80x80 in the replacement pack; runtime source frames retain their
original symmetric padding and foot anchors. No world props, placements or
collisions are changed. Generated logs and review PNGs stay outside the repo.

## Execution record

- Reproduced the missing chin with original-pixel probes before restoring the
  independent complete head. Crown/hair colors and original RGBA are preserved.
- Independent PNG review identified robe triangles inside the supplied head
  cut. Crown-connected hair/face contours remove them. Source shirt colors can
  match hair shadows, so disconnected shoulder clusters must be excluded.
- Removing the old cloth bridge exposed rear neck gaps. Ruling: calibrate the
  complete head anchor by 1–2 native pixels in 15 poses; preserve head, torso
  and leg geometry. The regression checks contact at actual sprite transforms.
- Reproduced crossbow face intersections, then swept all 27 registered weapons.
  The sweep exposed additional mace/warmaul/bow/staff walk-phase collisions.
  Ruling: adjust the affected per-direction carry angles about the existing grip
  after evaluating all idle/walk phases, bare and armored; no hand offsets.
- A connected crossbow source split into orphan pixels after inverse nearest
  rotation. A failing connectivity test reproduced this. Conservatively retain
  connected native source centers and links, copying source palette colors only.
- A minimized render window stalled frame_post_draw during batch review.
  Explicit SubViewport force_draw fixed the observed hang; minimized real
  OpenGL export tests pass. No game rendering settings are changed.
- Actual PNG evidence covers all 27 weapon visuals, all 72 poses, bare and with
  armor/capes (3,888 renders), plus 432 cape-only renders and 1x/4x head views.
  Independent visual/code review found no important remaining issue in reviewed
  corrected samples; it did not inspect every exported frame or grant art approval.
- Cape sample review found no demonstrated attachment/layering defect. Ruling:
  preserve existing cape art/motion; do not invent cloth animation without a
  demonstrated fault. Attack animations are the existing game behavior.
- Preserve the unrelated preview-only weapon-picker hunk in sprite_preview.gd;
  only the explicit capture-render change belongs to this repair.

Validation: equipment identity, transformed pose, attachment, fitted-equipment,
sprite integration and rendered/minimized inspector checks. Detailed logs and
captures remain in the supporting workspace. Commit/push after final scoped
index review; no generated diagnostics or unrelated work belongs in the commit.
