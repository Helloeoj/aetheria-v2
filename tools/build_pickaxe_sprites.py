"""Export preserved PixelLab sheets as actual directional held-equipment assets."""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_sources/pickaxes/held-v1'
MATERIALS = ['bronze','iron','steel','blacksteel','mithril','adamantite','runite']
DIRECTIONS = ['south','south-east','east','north-east','north','north-west','west','south-west']

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def replay(source, operations):
    result = source.copy()
    for op in operations:
        assert op['operation']=='map_colors' and op['frames']==[1]
        x0,y0,x1,y1 = op['region']
        before = result[y0:y1+1,x0:x1+1].copy()
        for old,new in op['colors'].items():
            a = tuple(int(old[i:i+2],16) for i in (1,3,5))
            b = tuple(int(new[i:i+2],16) for i in (1,3,5))
            mask = (before[:,:,3]==255) & np.all(before[:,:,:3]==a,axis=2)
            result[y0:y1+1,x0:x1+1,:3][mask] = b
    return result

def scene(material, grips, support_grips):
    lines = ['[gd_scene load_steps=10 format=3]','',
             '[ext_resource type="Script" path="res://scripts/equipment_visual_2d.gd" id="1"]']
    for i,d in enumerate(DIRECTIONS,2):
        lines.append(f'[ext_resource type="Texture2D" path="res://Assets/Equipment/Pickaxes/Held/{material}/{d}.png" id="{i}"]')
    lines += ['',f'[node name="{material.title()}Pickaxe" type="Node2D"]',
              'texture_filter = 1','script = ExtResource("1")','source_scale = 1.0',
              'keep_upright = true','weapon_family = "pickaxe"','metadata/attachment_socket = "right_hand"',
              'metadata/directional_views = 8','metadata/mining_swing_animation = false',
              'directional_textures = {']
    lines += [f'"{d}": ExtResource("{i}")'+(',' if i<9 else '') for i,d in enumerate(DIRECTIONS,2)]
    lines += ['}','grip_positions = {']
    lines += [f'"{d}": Vector2({grips[d][0]}, {grips[d][1]})'+(',' if i<7 else '') for i,d in enumerate(DIRECTIONS)]
    lines += ['}', '', 'support_grip_positions = {']
    lines += [f'"{d}": Vector2({support_grips[d][0]}, {support_grips[d][1]})'+(',' if i<7 else '') for i,d in enumerate(DIRECTIONS)]
    lines += ['}','','[node name="Artwork" type="Sprite2D" parent="."]',
              'texture_filter = 1','texture = ExtResource("2")','centered = false',
              f'position = Vector2({-grips["south"][0]}, {-grips["south"][1]})','']
    return '\n'.join(lines)

def build(output):
    output = Path(output).resolve()
    if SOURCE == output or SOURCE in output.parents:
        raise ValueError('Do not overwrite preserved source artwork.')
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Output must be new or empty.')
    operations = json.loads((SOURCE/'material-palette-operations.json').read_text(encoding='utf-8'))
    registration = json.loads((SOURCE/'directional-grips.json').read_text(encoding='utf-8'))
    grips = registration['grips']
    support_grips = registration['support_grips']
    original = np.array(Image.open(SOURCE/'pixellab-iron/iron-sheet.png').convert('RGBA'))
    assert original.shape==(40,320,4)
    output.mkdir(parents=True,exist_ok=True)
    (output/'scenes').mkdir()
    entries=[]
    for material in MATERIALS:
        sheet_path=SOURCE/'directional-sheets'/(material+'.png')
        sheet=np.array(Image.open(sheet_path).convert('RGBA'))
        expected=original if material=='iron' else replay(original,operations['operations'][material])
        if not np.array_equal(sheet,expected):
            raise ValueError(material+': saved PixelLab result differs from guarded palette replay.')
        assert np.array_equal(sheet[:,:,3],original[:,:,3])
        folder=output/'textures'/material
        folder.mkdir(parents=True)
        views={}
        for index,direction in enumerate(DIRECTIONS):
            pixels=sheet[:,index*40:(index+1)*40]
            alpha=pixels[:,:,3]
            x,y=grips[direction]
            assert alpha[y,x]==255,(material,direction,'grip outside tool')
            assert set(np.unique(alpha)) <= {0,255}
            assert not alpha[0].any() and not alpha[-1].any() and not alpha[:,0].any() and not alpha[:,-1].any()
            target=folder/(direction+'.png')
            Image.fromarray(pixels).save(target)
            views[direction]={'texture':f'res://Assets/Equipment/Pickaxes/Held/{material}/{direction}.png',
                              'grip':grips[direction],'sha256':sha(target)}
        (output/'scenes'/(material+'.tscn')).write_text(scene(material,grips,support_grips),encoding='utf-8')
        entries.append({'id':material,'name':material.title()+' Pickaxe',
                        'scene':f'res://scenes/equipment/pickaxes/{material}.tscn',
                        'source_sheet_sha256':sha(sheet_path),'views':views})
    manifest={'schema_version':2,'status':'installed directional art; final user review separate',
              'native_size':[40,40],'directions':DIRECTIONS,'entries':entries,
              'socket':'right_hand','component':'EquipmentVisual2D','source_scale':1,
              'world_pixels_per_source_pixel':0.75,
              'density_note':'Inherited from character; never apply scale twice.',
              'source_provider':'Built-in imagegen design; PixelLab eight-view object and free palette edits',
              'pixellab_object_id':'01ab845a-05df-4bad-865c-977345a7ccf7',
              'pixellab_rotation_generation_quote':1,'material_variants':'Free exact palette edits; shared alpha/wood/grip',
              'inventory_icons':False,'mining_swing_animation':False,'catalog_items_added':False,
              'approval':'User likes designs; directional artwork and rig review remain separate from automatic checks.'}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    return manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    data=build(args.output)
    print(json.dumps({'materials':len(data['entries']),'views_per_material':8,'native_pngs':56,'source_palette_replay':'exact'}))
