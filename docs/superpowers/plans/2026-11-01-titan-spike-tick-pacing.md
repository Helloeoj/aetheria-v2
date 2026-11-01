# Titan spike: tick pacing revision

User rejected the first effect's comedically fast pop. Preserve the stone design,
red warning, one shared asset per tile, approved Titan idle/slam and all map/game
behavior. Reuse source art; no new generation.

The actual combat tick is GameTickConfig.TICK_DURATION_SECONDS = 0.6. Sample
visuals smoothly between tick events: two ticks of warning, one full tick to
rise, one full tick to retract, no added dwell at full height. Use30 motion
steps/tick (20ms,50fps) and eased integer native-pixel travel. Keep one exact
51px peak frame, then begin descending on the next frame. Brief120ms cleanup
after the stone is below floor is presentation only.

The warning starts on a tick; start the unchanged slam180ms later so its1020ms
fist contact lands at1200ms (two ticks). Peak1800ms, below floor2400ms,
cleanup complete2520ms. No artwork frames or durations in the approved slam
are changed. This timing is an externally clocked VFX contract, not new server
boss/damage behavior.

1. First run a failing regression for the two-tick warning, full-tick up/down,
   <=3px motion steps and a unique peak. Preserve independent instances/import
   tests. Implement shared-tick sampling and rebuild71 native frames/atlas.
2. Update source verification, manifests, library region, docs and review helper
   for this timing. Check exact source pixels and all approved slam files remain
   unchanged. Reimport and compare actual imported pixels.
3. Render the same actual Golem Kingdom fixture at20ms sample intervals for3s,
   with real player, single-tile4x and ten independent tiles2x. Check geometry
   again and inspect rise/retract timeline. Package lossless duration-checked
   previews in a new tick-paced deliverable directory. Run passive worldbuilding
   against the actual updated atlas/fixture and retain unsupported-script status.
4. Review exact scoped changes; commit/push only task files on the existing Titan
   branch using an isolated index, preserving active checkout and unrelated work.

Review focus: both visual phases must last600ms; tick cadence must not become
one visual frame per tick; no duplicate peak dwell; slam contact must stay on
warning completion; old fast previews must not be presented as this revision.
