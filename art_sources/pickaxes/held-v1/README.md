# Directional held pickaxes

Seven materials (Bronze, Iron, Steel, Blacksteel, Mithril, Adamantite and Runite),
each with eight native 40 x 40 transparent views. Built-in imagegen supplied the
design the user liked; PixelLab supplied the eight-view Iron object and exact
material palette edits. Original generated designs, south references, PixelLab
views, operation recipes and receipts are preserved here. No new generation is
needed to reuse these assets.

Runtime PNGs are in `godot_client/Assets/Equipment/Pickaxes/Held/<material>/`.
The seven registered scenes in `godot_client/scenes/equipment/pickaxes/` bind
`EquipmentVisual2D` to the character's real `right_hand` socket. Primary and
support grips are in native source coordinates in `directional-grips.json`.
Source scale stays 1: the character supplies the 0.75 world-pixel density.
Scenes retain the existing pickaxe family and shared character-motion adapter.
Use the existing F7 character viewer, Peasant, and the Weapon picker to inspect
any material and direction.

From the repository root, with Python/Pillow/NumPy installed:

```powershell
python tools/build_pickaxe_sprites.py --output <new-empty-folder>
python -m unittest discover -s tools -p test_build_pickaxe_sprites.py -v
```

The builder exports into the selected folder; it does not install or replace
runtime artwork. It replays saved palette operations exactly and checks binary
alpha, transparent canvas borders and the primary grip. The regression checks
all 56 exported images against installed images and all seven exported scenes
against the current rig registration, including support grips/motion settings.

Completion review, 2026-11-03: the attachment smoke test passed 1,548 checks;
the real Godot 4x review passed all 56 registered views, lossless imports,
character density and zero primary-grip drift. The existing F7 picker was
captured. A focused Iron/south-east review in the actual East Outskirts scene
also passed, exercising real Main movement and inspecting idle/walk captures.
Machine-specific screenshots/logs stay outside Git in the supporting workspace.

The user liked the designs. Final directional-art approval remains pending;
automatic checks and local installation do not grant approval. This package
adds no inventory icons, item definitions, stats or mining gameplay. Existing
shared character motion is retained; dedicated mining-animation work is a
separate stage.
