"""Geometry from the reviewed painted-V3 floor trace, never replacement art.

The input is an authored/reviewed source-space floor mask, not a colour rule.
Room envelopes and all eight room/corridor seeds were checked against the exact
approved PNG. Two-source-pixel collision strips are conservative trace cells;
the gameplay movement grid remains32world pixels at origin(0,0).
"""
from pathlib import Path
from collections import deque
import argparse
import hashlib
import json
import math

import numpy as np
from PIL import Image
import valtherian_geometry as old

WORLD = (6144, 3328)
SOURCE_SIZE = (1703, 924)
SCALE = (6144/1703, 3328/924)
ROOM_SEEDS = {
    "far_west_chamber": (125,200), "upper_west_gallery": (850,100),
    "upper_east_chamber": (1100,120), "east_upper_chamber": (1590,150),
    "lower_west_gallery": (280,780), "lower_east_chamber": (1160,790),
    "west_combat_hall": (760,590), "east_combat_hall": (1130,445),
}
BRANCH_ROOMS = ["east_upper_chamber", "upper_east_chamber", "lower_east_chamber",
                "upper_west_gallery", "lower_west_gallery"]
# Actual Godot audit found these clear at the native rectangle boundaries.
# Classification only: their source trace/collision geometry is not changed.
ENGINE_CONFIRMED_FLOOR_CELLS = {(175,51), (175,62), (175,67)}


def component(allowed, start):
    previous = {start: None}
    queue = deque([start])
    while queue:
        x,y = queue.popleft()
        for point in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if point in allowed and point not in previous:
                previous[point] = (x,y)
                queue.append(point)
    return previous


def _overlap(bounds, polygon):
    left,top,right,bottom = bounds
    if right < min(p[0] for p in polygon) or left > max(p[0] for p in polygon) or bottom < min(p[1] for p in polygon) or top > max(p[1] for p in polygon):
        return False
    box = [(left,top),(right,top),(right,bottom),(left,bottom)]
    axes = [(1,0),(0,1)] + [(-(b[1]-a[1]), b[0]-a[0]) for a,b in zip(polygon,polygon[1:]+polygon[:1])]
    for ax,ay in axes:
        aa = [x*ax+y*ay for x,y in box]
        bb = [x*ax+y*ay for x,y in polygon]
        if max(aa) < min(bb) or max(bb) < min(aa):
            return False
    return True


def build(floor_mask_path, markers_path, repo_root, evidence_dir):
    repo_root, evidence_dir = Path(repo_root), Path(evidence_dir)
    evidence_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(floor_mask_path) as image:
        assert image.size == SOURCE_SIZE
        source_floor = np.array(image.convert("L")) > 0
    # Last source column is only one pixel wide; clip its world boundary below.
    padded = np.ones((924,1704), bool)
    padded[:,:1703] = source_floor
    coarse = padded.reshape(462,2,852,2).all(axis=(1,3))
    ys,xs = np.where(coarse)
    trace_cells = set(zip(xs.tolist(),ys.tolist()))
    arrival = [6032,2064]
    source_start = (int(arrival[0]/SCALE[0]/2),int(arrival[1]/SCALE[1]/2))
    assert source_start in trace_cells
    trace_cells = set(component(trace_cells, source_start))
    coarse[:] = False
    for x,y in trace_cells:
        coarse[y,x] = True
    rings = old.floor_polygons(trace_cells)
    assert len(rings) == 1, "Review separate islands or holes before installing"

    def coordinate(value, axis):
        return round(min(WORLD[axis], value/32*2*SCALE[axis]),6)

    polygon = [[coordinate(x,0),coordinate(y,1)] for x,y in rings[0]]
    void = []
    for x,y,w,h in old.merged_void_rects(trace_cells,(852,462)):
        left,top,right,bottom = coordinate(x,0),coordinate(y,1),coordinate(x+w,0),coordinate(y+h,1)
        if right > left and bottom > top:
            void.append([left,top,round(right-left,6),round(bottom-top,6)])
    void += [[-64,-64,6272,64],[-64,3328,6272,64],[-64,0,64,3328],[6144,0,64,3328]]
    index_x = np.floor((np.arange(6144)+.5)/SCALE[0]/2).astype(int)
    index_y = np.floor((np.arange(3328)+.5)/SCALE[1]/2).astype(int)
    world_floor = coarse[index_y[:,None],index_x[None,:]]
    wall_path = evidence_dir/"painted-v3-wall-or-void-world.png"
    Image.fromarray((~world_floor).astype(np.uint8)*255).save(wall_path)
    any_cells = {(x,y) for y in range(104) for x in range(192)
                 if world_floor[y*32:(y+1)*32,x*32:(x+1)*32].any()}
    markers = json.loads(Path(markers_path).read_text(encoding="utf-8"))
    ores = old.place_ores(markers,repo_root,any_cells,wall_path)
    assert all(not ore["moved"] for ore in ores), "Review any proposed actual-art conflict before moving a user mark"
    bases = []
    for ore in ores:
        asset = old._asset({"id":ore["id"],"ore":ore["ore"],"canonical_native_scene":ore["scene"]},repo_root)
        rx,ry = ore["root_world_xy"]
        bases += [[(rx+x,ry+y) for x,y in p] for p in asset["polygons"]]

    def clear(bounds, with_ores=True):
        left,top,right,bottom = bounds
        if left < 0 or top < 0 or right > 6144 or bottom > 3328:
            return False
        x0 = max(0,math.floor(left/(2*SCALE[0])))
        y0 = max(0,math.floor(top/(2*SCALE[1])))
        x1 = min(852,math.ceil(right/(2*SCALE[0])))
        y1 = min(462,math.ceil(bottom/(2*SCALE[1])))
        return bool(coarse[y0:y1,x0:x1].all()) and (not with_ores or not any(_overlap(bounds,p) for p in bases))

    def box(point,width):
        x,y = point
        half = width/2
        return (x-half,y-half,x+half,y+half)

    nominal_cells = {(x,y) for y in range(104) for x in range(192)
                     if clear(box((x*32+16,y*32+16),24.2),False)}
    nominal_cells.update(ENGINE_CONFIRMED_FLOOR_CELLS)
    allowed = {p for p in nominal_cells if clear(box((p[0]*32+16,p[1]*32+16),24.2))}
    body_start = ((arrival[0]-16)//32,(arrival[1]-16)//32)
    assert body_start in allowed
    body_previous = {body_start:None}
    queue = deque([body_start])
    while queue:
        x,y = queue.popleft()
        for point in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if point not in allowed or point in body_previous:
                continue
            a,b = (x*32+16,y*32+16),(point[0]*32+16,point[1]*32+16)
            bounds = (min(a[0],b[0])-12.1,min(a[1],b[1])-12.1,max(a[0],b[0])+12.1,max(a[1],b[1])+12.1)
            if clear(bounds):
                body_previous[point] = (x,y)
                queue.append(point)
    isolated_body_cells = sorted(allowed-set(body_previous))
    for ore in ores:
        candidates = [p for p in ore["approach_candidates"]
                      if ((p["world_xy"][0]-16)//32,(p["world_xy"][1]-16)//32) in body_previous]
        assert candidates, f"No actual-floor approach for {ore['id']}"
        ore["approach_candidates"] = candidates
        ore["approach_world_xy"] = candidates[0]["world_xy"]
        ore["approach_status"] = "Actual traced-floor/base-clear and body-swept connected; final Godot physics remains required"

    # Protected routes may use16px authoring points; gameplay still uses32px.
    # Adjacent48.2px endpoint squares overlap, proving their cardinal sweep.
    lanes = {(x,y) for y in range(209) for x in range(385)
             if clear(box((x*16,y*16),48.2))}
    lane_start = (arrival[0]//16,arrival[1]//16)
    assert lane_start in lanes
    lane_previous = component(lanes,lane_start)

    def nearest(nodes, source_point, step, offset=0):
        target = ((source_point[0]+.5)*SCALE[0],(source_point[1]+.5)*SCALE[1])
        return min(nodes,key=lambda p: ((p[0]*step+offset-target[0])**2+(p[1]*step+offset-target[1])**2,p[1],p[0]))

    room_probes = {name:[p[0]*32+16,p[1]*32+16]
                   for name,seed in ROOM_SEEDS.items()
                   for p in [nearest(body_previous,seed,32,16)]}
    targets = {name:nearest(lane_previous,seed,16) for name,seed in ROOM_SEEDS.items()}

    def path(previous, target):
        points = [target]
        while previous[points[-1]] is not None:
            points.append(previous[points[-1]])
        return points[::-1]

    main = path(lane_previous,targets["far_west_chamber"])
    branch_previous = {p:None for p in main}
    queue = deque(main)
    while queue:
        x,y = queue.popleft()
        for p in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if p in lanes and p not in branch_previous:
                branch_previous[p] = (x,y)
                queue.append(p)
    paths = {"approved-main":main}
    paths.update({name:path(branch_previous,targets[name]) for name in BRANCH_ROOMS})
    routes = []
    for name,points in paths.items():
        world = [[x*16,y*16] for x,y in points]
        turns = [world[0]] + [p for i,p in enumerate(world[1:-1],1)
                                if not (world[i-1][0]==p[0]==world[i+1][0] or world[i-1][1]==p[1]==world[i+1][1])] + [world[-1]]
        for i,(a,b) in enumerate(zip(turns,turns[1:])):
            width = 48
            for candidate in range(50,258,2):
                half = (candidate+.2)/2
                if not clear((min(a[0],b[0])-half,min(a[1],b[1])-half,max(a[0],b[0])+half,max(a[1],b[1])+half)):
                    break
                width = candidate
            routes.append({"id":f"{name}-{i:02d}","points":[a,b],"width":width})
    result = {"schema":1,"status":"Reviewed exact-image trace; actual Godot validation pending",
              "world_size":list(WORLD),"gameplay_cell_pixels":32,"grid_origin":[0,0],
              "floor_cells":[list(p) for p in sorted(nominal_cells,key=lambda p:(p[1],p[0]))],
              "floor_polygon":polygon,"void_rects":void,"ores":ores,
              "arrival":arrival,"room_probes":room_probes,"routes":routes,
              "trace_source_size":list(SOURCE_SIZE),"collision_trace_source_pixel_step":2,
              "source_floor_trace_sha256":hashlib.sha256(Path(floor_mask_path).read_bytes()).hexdigest(),
              "authored_wall_exclusions_source_xywh":[{"rect":[929,54,11,33],"reason":"Reviewed warm timber/torch post; a24px body at source~927,75 intersects this painted support."}],
              "engine_confirmed_floor_classification_cells":[list(p) for p in sorted(ENGINE_CONFIRMED_FLOOR_CELLS)],
              "wall_or_void_mask":wall_path.name,
              "checks":{"body_clear_cells":len(allowed),"body_reachable_cells":len(body_previous),
                        "ore_count":len(ores),"nodes_moved":0,"main_route_present":True,
                        "branches":5,"minimum_reserved_lane":min(r["width"] for r in routes),
                        "isolated_cardinal_body_cells_for_review":[list(p) for p in isolated_body_cells]},
              "trace_review":"Authored room-envelope corrections and room/corridor seeds exclude warm timber/wall faces; reviewed source floor mask is explicit input, never runtime colour classification.",
              "limits":"Conservative2source-pixel geometry, no art changes or new generation. Exact map pixels and canonical ore textures unchanged. Actual Godot physics/render/travel checks remain required."}
    output = evidence_dir/"approved-v3-geometry-draft.json"
    output.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--floor-mask",required=True,type=Path)
    parser.add_argument("--markers",required=True,type=Path)
    parser.add_argument("--evidence-dir",required=True,type=Path)
    parser.add_argument("--repo",type=Path,default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    output = build(args.floor_mask,args.markers,args.repo,args.evidence_dir)
    print(json.dumps({"checks":output["checks"],"polygon_vertices":len(output["floor_polygon"]),"void_rectangles":len(output["void_rects"]),"protected_segments":len(output["routes"])}))
