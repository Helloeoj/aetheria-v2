"""Assemble approved cells, complete native wall props and user-marked ores.

Artwork is never resized/recoloured here. Wall masks are analysis-only data.
Run the Godot content exporter after this data builder, then the real gate.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
from PIL import Image
from valtherian_geometry import build_floor, floor_polygons, merged_void_rects, place_ores

REPO = Path(__file__).resolve().parents[1]
AREA = REPO / 'godot_client/Assets/Maps/ValtherianMines'
SOURCE = REPO / 'art_sources/valtherian-mines'
WORLD = (6144, 3328)

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))

def write(path, data):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, indent=2)+'\n', encoding='utf-8')

def portable(value):
    if isinstance(value, dict):
        return {k: portable(v) for k,v in value.items()}
    if isinstance(value, list):
        return [portable(v) for v in value]
    if isinstance(value, str) and (value.startswith('C:/') or value.startswith('C:\\')):
        return Path(value.replace('\\','/')).name
    return value

def wall_instances(cells, units):
    ring = {}
    for x,y in sorted(cells, key=lambda p:(p[1],p[0])):
        for dx,dy,side in [(0,-1,'north'),(0,1,'south'),(-1,0,'west'),(1,0,'east')]:
            p=(x+dx,y+dy)
            if p in cells:
                continue
            # The approved right-edge arrival tunnel stays visually open.
            if p[0] >= 192 and 61 <= p[1] <= 66:
                continue
            ring.setdefault(p,set()).add(side)
    walls=[]
    for i,((x,y),sides) in enumerate(sorted(ring.items(),key=lambda v:(v[0][1],v[0][0]))):
        if 'south' in sides:
            variant=3
        elif 'north' in sides:
            variant=(abs(x*17+y*31)%3)
        elif len(sides)>1:
            variant=5
        else:
            variant=4
        u=units[variant]
        # Low foreground caps meet the floor edge with a small visual overlap;
        # their27px native silhouette otherwise leaves a4px strip of void.
        root_y=(y+1)*32-(8 if variant==3 else 0)
        walls.append({'name':f'Wall{i:04d}', 'scene':u['scene'], 'variant':u['id'],
                      'position':[x*32+16,root_y], 'wall_cell':[x,y],
                      'boundary_sides':sorted(sides)})
    return walls

def wall_analysis_mask(walls,units,out):
    mask=Image.new('L',WORLD,0)
    variants={u['id']:u for u in units}
    cache={}
    for key,u in variants.items():
        path=REPO/'godot_client'/u['texture'].removeprefix('res://')
        with Image.open(path) as image:
            alpha=image.getchannel('A').point(lambda v:255 if v else 0)
        factor=round(1/u['world_pixels_per_source_pixel'])
        assert factor*u['world_pixels_per_source_pixel']==1
        assert all(v%factor==0 for v in u['anchor']), 'Keep source anchors on whole-world pixels'
        padded=Image.new('L',(math.ceil(alpha.width/factor)*factor,math.ceil(alpha.height/factor)*factor),0)
        padded.paste(alpha,(0,0))
        reduced=padded.resize((padded.width//factor,padded.height//factor),Image.Resampling.BOX).point(lambda v:255 if v else 0)
        cache[key]=(reduced,[int(v/factor) for v in u['anchor']])
    for w in walls:
        small,anchor=cache[w['variant']]
        left=w['position'][0]-anchor[0]
        top=w['position'][1]-anchor[1]
        mask.paste(255,(left,top,left+small.width,top+small.height),small)
    mask.save(out)
    return mask

def decor_instances(contract,walls,units):
    """Mount whole supports at actual back-wall feet, clear of floor lanes."""
    if not units:
        return []
    result=[]
    for room in contract['rooms']:
        x,y,w,h=room['clear_rect_cells']
        center=(x+w/2)*32
        candidates=[v for v in walls if 'north' in v['boundary_sides']
                    and v['wall_cell'][1]==y-2 and x*32<=v['position'][0]<(x+w)*32]
        assert candidates, 'No actual back wall for '+room['id']
        chosen=min(candidates,key=lambda v:(abs(v['position'][0]-center),v['position'][0]))
        unit=units[0]
        result.append({'name':'Lantern'+''.join(s.title() for s in room['id'].split('_')),
                       'scene':unit['scene'],'variant':unit['id'],'position':chosen['position'],
                       'room_id':room['id'],'mounted_on':chosen['name']})
    return result

def build(markers_path,wall_manifest,evidence_dir):
    contract=read(SOURCE/'planning/tile-layout-v3.json')
    cells=build_floor(contract)
    assert len(cells)==5498
    units=read(wall_manifest)['units']
    assert len(units)==6
    walls=wall_instances(cells,units)
    decor_manifest=AREA/'decor-props.json'
    decor_units=read(decor_manifest)['units'] if decor_manifest.exists() else []
    decor=decor_instances(contract,walls,decor_units)
    evidence_dir.mkdir(parents=True,exist_ok=True)
    mask_path=evidence_dir/'valtherian-wall-alpha-world.png'
    wall_analysis_mask(walls+decor,units+decor_units,mask_path)
    markers=read(markers_path)
    assert markers['counts']=={'blackstone':12,'mithril':4,'adamantite':2,'coal':7,'iron':4}
    ores=place_ores(markers,REPO,cells,wall_mask_path=mask_path)
    for record in ores:
        record['name']=''.join(word.title() for word in record['id'].replace('-','_').split('_'))
        record['scene']=record.get('scene',record.get('canonical_native_scene'))
        if not record['scene']:
            marker=next(m for m in markers['markers'] if m['id']==record['id'])
            record['scene']=marker['canonical_native_scene']
        record['position']=record['root_world_xy']
    polygons=floor_polygons(cells)
    assert len(polygons)==1,'Review any introduced island/hole explicitly'
    void=merged_void_rects(cells)
    void += [[-64,-64,6272,64],[-64,3328,6272,64],[-64,0,64,3328],[6144,0,64,3328]]
    layout={'schema':1,'status':'Authored native map; actual scene validation required',
            'world_size':list(WORLD),'gameplay_cell_pixels':32,'grid_origin':[0,0],
            'floor_cells':[list(c) for c in sorted(cells,key=lambda p:(p[1],p[0]))],
            'floor_polygon':polygons[0],'void_rects':void,'wall_props':walls,'decor_props':decor,'ores':ores,
            'rooms':contract['rooms'],'main_route_cells':contract['main_route_cells'],
            'branches':contract['branches'],'source_tile_contract':'art_sources/valtherian-mines/planning/tile-layout-v3.json',
            'wall_asset_manifest':'Assets/Maps/ValtherianMines/wall-props.json',
            'scope':'Environment/placement only; no mining rules, enemies or skill progression'}
    write(AREA/'layout.json',layout)
    saved_markers=portable(copy.deepcopy(markers))
    saved_markers['status']='User marker authority with documented actual-floor/wall corrections'
    saved_markers['placements']=ores
    saved_markers['source_annotation']='art_sources/valtherian-mines/approved/user-ore-annotation-2026-10-28.png'
    write(AREA/'ore-markers.json',saved_markers)
    props=[{'node':'Walls/'+w['name'],'blocking':False,
            'reason':'Whole wall cladding; its solid footprint is owned by the actual authored continuous CaveBoundary geometry.'} for w in walls]
    props += [{'node':'Decor/'+d['name'],'blocking':False,
               'reason':'Whole timber/lantern mounted at an actual back-wall foot; continuous CaveBoundary owns the support base outside walking floor.'} for d in decor]
    props += [{'node':'Ores/'+o['name'],'blocking':True} for o in ores]
    anchors=[{'id':'arrival','point':[6032,2064]},{'id':'exit-approach','point':[6032,2064]}]
    for room in contract['rooms']:
        x,y,w,h=room['clear_rect_cells']
        anchors.append({'id':room['id'],'point':[(x+w//2)*32+16,(y+h//2)*32+16]})
    for ore in ores:
        anchors.append({'id':ore['id']+'-approach','point':ore['approach_world_xy']})
    main=copy.deepcopy(contract['main_route_cells'])
    # Keep the full192px sweep inside the map at its arrival endpoint.
    # This clips only the validation centerline, never the authored tunnel.
    main[0]=[188,64]
    routes=[{'id':'main-six-cell-haul-route','points':[[x*32,y*32] for x,y in main],'width':192}]
    routes += [{'id':b['id'],'points':[[x*32,y*32] for x,y in b['points']],'width':128} for b in contract['branches']]
    assets=[{'texture':u['texture'],'native_size':u['native_size'],'anchor':u['anchor'],
             'world_pixels_per_source_pixel':u['world_pixels_per_source_pixel'],
             **{k:u[k] for k in ('alpha_reason','components_reason','edge_reason') if k in u}} for u in units+decor_units]
    textures=set()
    for ore in ores:
        tex=ore.get('texture')
        if not tex:
            stem={'blackstone':'blackstone','coal':'coal','mithril':'mithril-ore','adamantite':'adamantite-ore','iron':'iron-ore'}[ore['ore']]
            tex='res://Assets/MapTiles/OreNodes/'+stem+'-full-south.png'
        if tex not in textures:
            assets.append({'texture':tex,'native_size':[96,96],'anchor':[48,72],'world_pixels_per_source_pixel':1})
            textures.add(tex)
    gate={'schema_version':1,'scene':'res://scenes/ValtherianMinesContent.tscn','bounds':[0,0,*WORLD],
          'grid_origin':[0,0],'floor_polygon':polygons[0],'props':props,'anchors':anchors,'routes':routes,'assets':assets}
    write(AREA/'worldbuilding.json',gate)
    print(json.dumps({'floor_cells':len(cells),'wall_props':len(walls),'decor_props':len(decor),'ores':len(ores),
                      'moved':[{'id':o['id'],'delta':o['delta_world_xy'],'reason':o['correction_reasons']} for o in ores if o['moved']],
                      'void_rectangles':len(void),'wall_mask':str(mask_path)}))

if __name__=='__main__':
    raise SystemExit('The modular Valtherian rebuild was rejected by the user. Do not reinstall it. Use the exact approved-image restoration workflow; no replacement art generation.')
