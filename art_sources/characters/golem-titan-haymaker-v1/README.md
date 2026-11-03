# Golem Titan haymaker candidate

A close-range physical side hook with a slight stable upper-body lean.
Cyan crystals and red eyes retain the original design. No magic, ground
warning, shockwave, floor disk or motion trail is added.

The source uses14 explicit18-joint poses from one approved neutral sprite.
All hip, knee and ankle coordinates are identical in every pose; the head and
neck are also identical throughout the main wind-up/strike poses3-10.
Complete fist and thumb are redrawn together, without rotating image chunks.

Native256x256, density1, anchor128,216. The original sprite was translated up
24 native pixels to leave clear canvas margin; runtime anchor compensation
retains the existing world scale and foot position. PNGs are lossless, binary
alpha, nearest filtered and have no mipmaps.

The existing Titan attack speed is3 ticks. Two600ms ticks of anticipation lead
to contact at1200ms; sweep and recovery finish at1800ms. Native contact192,201
is checked against the actual player's upper body within the unchanged2-cell
melee reach on the flank. The visible player reference is1/8 through a normal
diagonal grid step, at offset60,4; no depth sorting is overridden. This corrects the previous excessive forward fold and
floor-height swing. Artwork remains a candidate for user review.

`res://scenes/Effects/TitanHaymaker.tscn` is rooted at actor feet. Hide ordinary
actor artwork while sampling `sample_at_seconds(elapsed)`, then restore it when
returned phase is `complete`. It does not apply damage or install a boss AI
rotation. Existing idle, slam, casting, stats, collision and maps are unchanged.

`res://scripts/dev_tools/titan_haymaker_review.gd` loads the actual Golem Kingdom,
spawns the existing ID1029 Titan, checks every authored frame, and captures the
player and contact at4x. Failed candidate evidence remains outside Git in the
supporting workspace; this packet contains the selected sixth authorized pass.
