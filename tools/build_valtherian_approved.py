"""Install authored painted-map geometry and dots; never generate/repaint art."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
AREA=ROOT/'godot_client/Assets/Maps/ValtherianMines'
SOURCE=ROOT/'art_sources/valtherian-mines'
SHA='8ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90'

def write(path,data):
    path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')

def title(value):
    return ''.join(v.title() for v in re.split(r'[-_]',value))

def build(geometry):
    original=SOURCE/'unapproved/whole-map-v3.png'
    texture=AREA/'Approved/approved-map-v3.png'
    assert hashlib.sha256(original.read_bytes()).hexdigest()==SHA
    assert texture.read_bytes()==original.read_bytes(),'Approved pixels must remain unchanged'
    old=json.loads((AREA/'layout.json').read_text(encoding='utf-8'))
    data=copy.deepcopy(geometry)
    data['render_mode']='approved-image'
    data['approved_art']={'texture':'res://Assets/Maps/ValtherianMines/Approved/approved-map-v3.png',
                          'native_size':[1703,924],'world_size':[6144,3328],'source_sha256':SHA,
                          'policy':'Original approved image; no repaint, substitute wall kit or generation'}
    data['wall_props']=[]
    data['decor_props']=[]
    data['rooms']=old['rooms']
    data['main_route_cells']=old['main_route_cells']
    data['branches']=old['branches']
    data['status']='Exact approved image and authored painted-floor geometry; see restoration acceptance'
    for ore in data['ores']:
        ore['name']=title(ore['id'])
        ore['position']=ore['root_world_xy']
        assert ore['position']==ore['rounded_target_root_world_xy'],'Move only a documented real conflict'
    write(AREA/'layout.json',data)
    markers=json.loads((AREA/'ore-markers.json').read_text(encoding='utf-8'))
    markers['status']='Exact approved painted-map targets restored; real floor/foreground checks separate'
    markers['placements']=data['ores']
    write(AREA/'ore-markers.json',markers)
    anchors=[{'id':'arrival','point':data['arrival']},{'id':'exit-approach','point':data['arrival']}]
    anchors += [{'id':k,'point':v} for k,v in data['room_probes'].items()]
    anchors += [{'id':o['id']+'-approach','point':o['approach_world_xy']} for o in data['ores']]
    assets=[]
    seen=set()
    for ore in data['ores']:
        if ore['texture'] not in seen:
            assets.append({'texture':ore['texture'],'native_size':[96,96],'anchor':[48,72],'world_pixels_per_source_pixel':1})
            seen.add(ore['texture'])
    gate={'schema_version':1,'scene':'res://scenes/ValtherianMinesContent.tscn','bounds':[0,0,6144,3328],
          'grid_origin':[0,0],'floor_polygon':data['floor_polygon'],
          'props':[{'node':'Ores/'+o['name'],'blocking':True} for o in data['ores']],
          'anchors':anchors,'routes':data['routes'],'assets':assets}
    write(AREA/'worldbuilding.json',gate)
    # Runtime navigation probes use reviewed actual-floor points, not the rejected
    # rectangular image reconstruction. Preserve the same67-probe coverage.
    probes=[('EntranceApproach',data['arrival'])]
    probes += [('Room'+title(k),v) for k,v in data['room_probes'].items()]
    def points(prefix):
        routes=[r for r in data['routes'] if r['id'].startswith(prefix+'-')]
        return [routes[0]['points'][0]]+[r['points'][-1] for r in routes]
    main=points('approved-main')
    probes += [(f'MainRoute{i+1:02d}',main[round(i*(len(main)-1)/13)]) for i in range(14)]
    for name in ['east_upper_chamber','upper_east_chamber','lower_east_chamber','upper_west_gallery','lower_west_gallery']:
        branch=points(name)
        probes += [('Branch'+title(name)+str(i+1),branch[round(i*(len(branch)-1)/2)]) for i in range(3)]
    probes += [('OreApproach'+o['name'],o['approach_world_xy']) for o in data['ores']]
    assert len(probes)==67
    wrapper=ROOT/'godot_client/scenes/ValtherianMines.tscn'
    scene=wrapper.read_text(encoding='utf-8')
    start=scene.index('[node name="GridProbes"')
    finish=scene.index('[node name="Combat"',start)
    section='[node name="GridProbes" type="Node2D" parent="."]\n\n'
    for name,point in probes:
        section+=f'[node name="{name}" type="Marker2D" parent="GridProbes"]\nposition = Vector2({point[0]}, {point[1]})\n\n'
    wrapper.write_text(scene[:start]+section+scene[finish:],encoding='utf-8')
    print(json.dumps({'original_pixels_unchanged':True,'ores':len(data['ores']),'ore_moves':0,
                      'collision_rects':len(data['void_rects']),'navigation_probes':len(probes)}))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--geometry',type=Path,default=SOURCE/'planning/approved-image-geometry.json')
    args=parser.parse_args()
    build(json.loads(args.geometry.read_text(encoding='utf-8')))
