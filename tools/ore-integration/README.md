# Native128 ore integration

`original-library.json` and `original-scenes.json` record the unchanged native96
library before the clarity artwork is installed. They preserve the scene names,
palette IDs, physical base polygons, world anchors and source checksums.

From the repository root, with the installed Python/Pillow/numpy runtime:

```powershell
& $PythonExe tools/install_ore_clarity.py --check
& $PythonExe tools/install_ore_clarity.py --apply
& $PythonExe -m unittest discover -s tools -p test_ore_clarity.py -v
& $PythonExe -m unittest discover -s tools -p test_valtherian_geometry.py -v
& $GodotExe --headless --path godot_client --script res://tools/ore_node_library_smoke.gd --log-file <outside-repository>/ore-library.log
```

To reproduce the artwork from the two preserved generated PNGs, without
generation calls or installation:

```powershell
& $PythonExe tools/build_ore_clarity.py --output <new-empty-output-folder>
& $PythonExe -m unittest discover -s tools -p test_build_ore_clarity.py -v
```

The builder reads the original96 source palettes and immutable library snapshot,
registers each whole boulder separately, derives one finite shared host palette
and one mineral mask, and writes twenty variants plus `vein-mask.png`,
`shared-alpha.png`, `shared-host.png` and `build-report.json`. It rejects canonical
source/runtime output paths and nonempty destinations. The report records input
checksums, Pillow/numpy versions and output checksums; it contains no artwork
approval or installation decision. Tests reproduce all23 accepted PNG byte
hashes in temporary folders and exercise a portable repository containing only
the required source inputs, without installed Godot assets or runtime manifest.

The installer expects twenty RGBA PNGs with their original basenames under
`art_sources/ore-nodes/detail-v1/`. An optional `vein-mask.png` declares mineral
pixels; all other RGB pixels must match the one byte-identical depleted host.
Without that mask, every full variant must have the identical RGB-difference
support against the depleted host. All twenty alpha channels must match the
original96 alpha rerasterized128 with Pillow BILINEAR and threshold128.

Runtime copies go into `godot_client/Assets/MapTiles/OreNodes/Detail128/`.
Original96 assets remain untouched. Only canonical scene texture references,
Visual scale/native-image-anchor metadata and manifest art declarations change.
Native128 at Visual scale.75 retains the original96-world-pixel canvas,
Visual position(-48,-72), world foot anchor(48,72), root scale1 and both base
colliders. Scene names, palette IDs, placement transforms and gameplay remain.

The default check never writes. Apply validates the whole batch before writing
and refuses unexpected canonical scene edits or unrecognized manifest fields.
It preserves existing engine-generated import UIDs on subsequent applications.

These automatic checks do not grant artwork approval or validate a map.
Installation still requires the actual scene/placement contract, worldbuilding
checks and real Godot4x review with the player. Track automatic results,
visual approval and installation separately; save generated reports outside Git.
