"""Package intact, PixelLab-cleaned native wall exports without editing pixels."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAMES = ['WallBackA', 'WallBackB', 'WallBackC', 'WallFrontLow', 'WallSide', 'WallCorner']
ANCHORS = [[280,504], [248,504], [232,504], [320,432], [192,440], [248,440]]
REGIONS = [[0,0,560,512], [560,0,504,512], [1064,0,472,512],
           [0,512,632,512], [632,512,408,512], [1040,512,496,512]]
IDS = ['abe3cef3-3c8e-4529-b8e6-6425ae791535','0c7ec68f-4149-42ce-9b1f-b2c6b22b4002',
       '1fbc8fef-5c5a-4e58-bffe-1e42df22a161','226687be-6101-405e-8a71-8b1dd4a8ea3b',
       'ff3a450a-62c9-41e0-bdc6-78afe0d6f525','9705f738-8f75-4036-9772-70d12237dd3e']

def package(source):
    target = ROOT/'godot_client/Assets/Maps/ValtherianMines/Props'
    scenes = ROOT/'godot_client/scenes/MapProps/ValtherianMines'
    target.mkdir(parents=True, exist_ok=True)
    scenes.mkdir(parents=True, exist_ok=True)
    units=[]
    for i,name in enumerate(NAMES):
        src=source/f'wall-{i:02d}.clean.png'
        image=Image.open(src)
        assert image.mode=='RGBA' and image.size==tuple(REGIONS[i][2:])
        texture=f'res://Assets/Maps/ValtherianMines/Props/{name}.png'
        scene=f'res://scenes/MapProps/ValtherianMines/{name}.tscn'
        shutil.copyfile(src, target/f'{name}.png')
        ax,ay=ANCHORS[i]
        (scenes/f'{name}.tscn').write_text(f'''[gd_scene load_steps=2 format=3]

[ext_resource type="Texture2D" path="{texture}" id="1_texture"]

[node name="{name}" type="Node2D"]
y_sort_enabled = false
texture_filter = 1
metadata/native_canvas = Vector2i({image.width}, {image.height})
metadata/source_anchor = Vector2i({ax}, {ay})
metadata/world_pixels_per_source_pixel = 0.125
metadata/boundary_cladding = true

[node name="Visual" type="Sprite2D" parent="."]
position = Vector2({-ax/8}, {-ay/8})
scale = Vector2(0.125, 0.125)
texture_filter = 1
texture = ExtResource("1_texture")
centered = false
''', encoding='utf-8')
        units.append({'id':name,'texture':texture,'scene':scene,'native_size':list(image.size),
                      'anchor':[ax,ay],'world_pixels_per_source_pixel':0.125,
                      'visible_source_bounds':list(image.getchannel('A').getbbox()),
                      'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
                      'whole_sheet_region_xywh':REGIONS[i],'pixellab_edit_id':IDS[i],
                      'alpha_reason':'Stone surfaces retain original near-opaque alpha252-254 and narrow silhouette coverage alpha128-251. PixelLab removed the observed alpha1-127 background matte; the remaining silhouette is one connected component. Review on light/dark/ground and real4x is recorded separately.',
                      'physics':'Nonblocking wall cladding. Actual continuous CaveBoundary owns the solid footprint; never stack duplicate collision bases.'})
    manifest={'schema':1,'status':'Native complete props; actual placement and visual review required',
              'source':'Built-in imagegen wall sheet v2, whole nonresampled exports; exact prompts and source preserved in art_sources/valtherian-mines/native-walls/',
              'cleanup':'PixelLab free deterministic edit: alpha1-127 selection, masked eraser. Foreground RGBA128-255 byte-identical to native source; no regrid, scaling, recolour or blur.',
              'units':units}
    (target.parent/'wall-props.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    palette_units=units[:]
    decor=target.parent/'decor-props.json'
    if decor.exists():
        palette_units += json.loads(decor.read_text(encoding='utf-8'))['units']
    palette=[f'[gd_resource type="TileSet" load_steps={len(palette_units)+2} format=3]', '']
    palette += [f'[ext_resource type="PackedScene" path="{u["scene"]}" id="{i+1}"]' for i,u in enumerate(palette_units)]
    palette += ['', '[sub_resource type="TileSetScenesCollectionSource" id="Walls"]',
                'resource_name = "Valtherian Mine Whole Walls"']
    palette += [f'scenes/{i}/scene = ExtResource("{i+1}")' for i in range(len(palette_units))]
    palette += ['', '[resource]', 'tile_size = Vector2i(32, 32)', 'sources/0 = SubResource("Walls")', '']
    (ROOT/'godot_client/Assets/Tilesets/ValtherianMinesWalls.tres').write_text('\n'.join(palette),encoding='utf-8')
    print(json.dumps({'units':len(units),'native_density':0.125,'pixel_edits_in_packager':False}))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('source',type=Path)
    package(parser.parse_args().source)
