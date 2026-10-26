"""Build native Godot geometry/UV occluders around the approved, unmodified PNG.

No image generation, resampling, repainting or extraction is performed. Run from
any directory with Python; source artwork lives in art_sources/tavern-v1/.
"""
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'godot_client'
SOURCE = ROOT / 'art_sources/tavern-v1'
OUT = GAME / 'Assets/Maps/Tavern'


def vector(point):
    return f'Vector2({point[0]}, {point[1]})'


def packed(points):
    return 'PackedVector2Array(' + ', '.join(str(n) for p in points for n in p) + ')'


def rectangle(x, y, w, h):
    return [[x, y], [x+w, y], [x+w, y+h], [x, y+h]]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / 'approved-interior-v1.png', OUT / 'Interior.png')
    objects = []

    def add(name, visual, collision=None):
        foot = [sum(p[0] for p in visual)/len(visual), max(p[1] for p in visual)]
        objects.append(dict(name=name, foot=foot, polygon=visual, collision=collision))

    # Each source-space polygon samples the original PNG at the exact same UVs.
    # Narrow polygons follow silhouettes; the original base remains byte-exact.
    add('BarCounter', [[169,158],[213,158],[213,220],[737,222],[737,273],[208,282],[172,263]], [172,226,566,57])
    add('BarReturn', rectangle(172,158,42,125), [172,158,42,125])
    for i in range(9):
        x = 217 + i*57
        add(f'BarStool{i+1}', [[x,278],[x+26,274],[x+33,290],[x+26,321],[x,321],[x-5,293]], [x,290,25,29])
    add('KitchenDivider', rectangle(802,16,55,349), [802,0,55,365])
    add('KitchenRearCounter', rectangle(865,128,151,86), [865,128,151,86])
    add('Stove', rectangle(1015,133,155,81), [1015,133,155,81])
    add('KitchenIsland', [[931,260],[1117,260],[1126,277],[1126,335],[931,335]], [933,277,190,58])
    add('KitchenSideCabinet', rectangle(1170,145,24,185), [1170,145,24,185])
    add('Hearth', [[477,560],[751,560],[766,570],[766,715],[754,728],[472,728],[464,717],[464,573]], [472,571,286,151])
    add('HearthNorthBench', rectangle(477,486,277,51), [478,506,275,31])
    add('HearthSouthBench', rectangle(477,750,277,54), [478,772,275,32])
    add('HearthWestBench', rectangle(395,545,39,204), [395,550,39,199])
    add('HearthEastBench', rectangle(799,545,40,204), [799,550,40,199])
    # Whole table-and-chair groups, with narrower physical bases below tabletops.
    add('NorthwestTable', [[102,363],[133,363],[133,384],[207,384],[209,414],[244,414],[244,494],[208,494],[208,521],[138,521],[138,501],[85,501],[85,413],[102,413]], [91,399,146,117])
    add('WestLongTable', [[119,598],[158,598],[158,610],[227,610],[227,642],[261,642],[261,734],[229,734],[229,784],[157,784],[157,757],[106,757],[106,635],[119,635]], [110,633,145,137])
    add('SouthwestTable', [[155,822],[184,822],[184,840],[228,840],[242,862],[242,928],[221,940],[208,965],[163,965],[163,951],[108,951],[108,854],[155,854]], [114,855,123,96])
    for name, x, y in [('NortheastTable',1001,376),('EastTable',1001,605),('SoutheastTable',1001,828)]:
        add(name, [[x+55,y],[x+87,y],[x+87,y+22],[x+143,y+22],[x+155,y+60],[x+147,y+118],[x+95,y+118],[x+95,y+146],[x+51,y+146],[x+51,y+121],[x,y+121],[x,y+51],[x+19,y+51],[x+19,y+24],[x+55,y+24]], [x+6,y+35,145,101])
    add('WestBooth', rectangle(83,973,327,109), [83,993,327,89])
    add('EastBooth', rectangle(844,973,344,109), [844,993,344,89])
    # Bounds include the near wall and a clear central doorway approach.
    obstacles = [[0,0,78,1254],[1194,0,60,1254],[0,0,1254,164],
                 [78,1082,496,172],[670,1082,524,172],[574,1140,96,114],
                 [76,181,52,150],[76,547,18,92],[1155,529,39,89]]
    obstacles += [obj['collision'] for obj in objects if obj['collision']]
    # User-authorized no-entry island: hearth, surrounding benches and all gaps
    # between them. Collision/navigation only; original artwork/UVs stay exact.
    obstacles.append([395,486,444,318])
    layout = dict(source_size=[1254,1254], world_pixels_per_source_pixel=0.75,
                  objects=objects, obstacles=obstacles,
                  entrance=[627,1040], stove_approach=[1145,242],
                  notes='Original RGB retained. UV foreground polygons provide depth sorting; moving furniture requires a separate clean floor/art variant.')
    (OUT/'layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    lines = ['[gd_scene load_steps=2 format=3]', '',
             '[ext_resource type="Texture2D" path="res://Assets/Maps/Tavern/Interior.png" id="1_art"]', '',
             '[node name="TavernContent" type="Node2D"]',
             'y_sort_enabled = true', 'texture_filter = 1', 'scale = Vector2(0.75, 0.75)', '',
             '[node name="ApprovedArtwork" type="Sprite2D" parent="."]',
             'z_index = -20', 'texture = ExtResource("1_art")', 'centered = false', '']
    for obj in objects:
        name, foot = obj['name'], obj['foot']
        polygon = [[p[0]-foot[0],p[1]-foot[1]] for p in obj['polygon']]
        lines += [f'[node name="{name}" type="Node2D" parent="."]',
                  'position = '+vector(foot), '',
                  f'[node name="Foreground" type="Polygon2D" parent="{name}"]',
                  'texture = ExtResource("1_art")', 'polygon = '+packed(polygon),
                  'uv = '+packed(obj['polygon']), '']
    # Near walls cover the actor correctly when standing behind their front face.
    for name, poly in [('NearWallWest',rectangle(7,1050,567,140)),('NearWallEast',rectangle(670,1050,575,140))]:
        foot=[0,1190]
        lines += [f'[node name="{name}" type="Node2D" parent="."]', 'position = Vector2(0, 1190)', '',
                  f'[node name="Foreground" type="Polygon2D" parent="{name}"]',
                  'texture = ExtResource("1_art")', 'polygon = '+packed([[x,y-1190] for x,y in poly]),
                  'uv = '+packed(poly), '']
    lines += ['[node name="PhysicalBases" type="StaticBody2D" parent="."]','collision_mask = 0','']
    for index, rect in enumerate(obstacles):
        lines += [f'[node name="Base{index:02d}" type="CollisionPolygon2D" parent="PhysicalBases"]',
                  'polygon = '+packed(rectangle(*rect)), '']
    (GAME/'scenes/TavernContent.tscn').write_text('\n'.join(lines))
    print(f'Tavern: {len(objects)} foreground objects, {len(obstacles)} collision bases; source PNG copied without pixel changes.')


if __name__ == '__main__':
    main()
