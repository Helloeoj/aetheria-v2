# Shared player weapon motions

User requirements: repair southeast head desync, cape glitches and pickaxes;
two-handed weapons must use both hands; implement real attacks once per Bronze
weapon family and reuse those tracks across corresponding material tiers.

Architecture: one resolved native pose drives the complete head, torso, arms,
cape/helmet and weapon. Preserve existing complete chest/leg artwork and source
pixels. A reusable articulated arm renderer uses native source contours and
two-bone joints. Held-item primary/support grips derive both wrists from the
same weapon transform. Bronze family tracks drive windup, action and recovery;
the existing ActorSprite animation clock drives frames, not an idle lunge.

1. Diagnose and measure actual motion: original/generated frame phase matches,
   but head registration differs by up to5px laterally. Resolve all72 head/body
   anchors; cape neck must follow the same generated pose and render below head.
2. Add shared weapon-family tracks, per-actor attack SpriteFrames, explicit
   support grips and two-hand ready poses. Keep shared skin caches immutable.
3. Render original native upper/forearm/hand contours with connected joints;
   preserve independent torso, head and legs/feet. Reuse source colors, no armor
   scaling to bare limbs and no whole-frame redraw/replacement of approved art.
4. Integrate the pickaxe adapter and all7 native source grip/support profiles.
5. Add failing regressions for missing attacks, support-hand contact, cross-tier
   track identity, head/cape registration, and arm connectivity. Review actual
   full frame sequences at1x/4x, including loop closure and all attack families.
6. Preserve unrelated dirty work. Commit/push only scoped validated changes in
   the active checkout to Helloeoj/aetheria-v2; keep visual approval separate.

Parallel audits completed: head/cape registration data + rebuild tool and tests;
pickaxe adapter + focused631-check smoke and existing1548-check attachment smoke.
No world prop placement, gameplay rules, character saves or other UI is changed.
