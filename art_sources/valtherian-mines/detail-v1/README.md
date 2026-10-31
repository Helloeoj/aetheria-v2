# Valtherian linework restoration sources

This retained source package reproduces the installed detail candidate without
image generation or machine-specific input paths. The user approved the pilot's
linework treatment; full-map visual acceptance and combined worldbuilding checks
remain separate from that style approval.

The immutable approved original remains
`godot_client/Assets/Maps/ValtherianMines/Approved/approved-map-v3.png`,
SHA256 `8ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90`.
World registration remains 6144×3328. Neither the floor trace, collision bases,
92 foreground sort feet nor the 29 ore root transforms are authored by this pack.

`regions/` contains all 23 retained original crops and untouched built-in
imagegen outputs. `jobs.json` records their exact source rectangles and relative
paths. `approved-style-reference.png` was a style-only input; source crops were
the edit targets. Exact prompts and generated output filenames are retained in
`restoration.prompt.txt` and `provenance.json`. There were 24 built-in calls:
one larger clarity test and 23 retained map regions. No PixelLab calls were used.

Single affine registrations correct generated crop framing; their matrices and
RGB reproduction hashes are in `registration-report.json`. Dense deformation
was trialled and rejected, and is not part of the retained pipeline. Region
joins use connected minimum-error hard cuts, never blended art. Final raster
sampling is nearest. Empty source regions outside restoration coverage are
reused from the original.

From the repository root, with Python, NumPy and Pillow:

```powershell
python tools/build_valtherian_detail.py --bind
```

The normal build uses the retained matrices directly and needs no OpenCV.
It reproduces every retained registered RGB pixel before assembling the master.
The master is 8192×4438 at 0.75×0.7498873366 world pixels per texel. The foreground
uses the original alpha geometry and takes its RGB from this same master.
`provenance.json` records the retained master checksum for byte comparison.
The runtime detail manifest includes source rectangles, raw hashes, affine
matrices, seam summaries, generation provenance and unchanged gameplay fingerprint.

`tools/register_valtherian_detail.py` is an optional authoring tool for deliberately
re-estimating registrations, and requires OpenCV. It is unnecessary for normal
reproduction; new registration choices require fresh visual and placement review.
After intentional artwork changes, import using the installed Godot and rerun
the actual map's worldbuilding, physics, route, travel and real 4× review gates.
The map material preserves the approved mine-specific 64-colour lookup and
stabilizes texel-boundary ties between the full master and packed foreground.
Actors, ores and UI do not inherit this material.
