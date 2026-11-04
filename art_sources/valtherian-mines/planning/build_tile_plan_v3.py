"""Author the requested larger-room layout in real 32-world-pixel cells.

This is a deterministic structural diagram/contract, not a runtime art texture.
It never resizes or edits the user's accepted-direction artwork.
"""
from pathlib import Path
from collections import deque
import json

OUT = Path(__file__).resolve().parent
CELL = 32
SIZE = (192, 104)
MAIN = [[192,64],[172,64],[156,64],[156,48],[140,48],[116,48],
        [104,48],[104,68],[84,68],[64,68],[64,40],[48,40],
        [36,40],[36,24],[16,24]]
BRANCHES = [
    {"id":"east_upper_branch", "points":[[172,64],[172,38],[178,38],[178,16]]},
    {"id":"upper_east_branch", "points":[[140,48],[140,32],[124,32],[124,14]]},
    {"id":"lower_east_branch", "points":[[116,48],[116,74],[132,74],[132,90]]},
    {"id":"upper_west_branch", "points":[[84,68],[84,30],[98,30],[98,12]]},
    {"id":"lower_west_branch", "points":[[48,40],[48,74],[32,74],[32,90]]},
]
ROOMS = [
    {"id":"far_west_chamber", "role_proposal":"destination/combat", "clear_rect_cells":[4,14,24,20]},
    {"id":"east_upper_chamber", "role_proposal":"combat", "clear_rect_cells":[168,8,20,16]},
    {"id":"upper_east_chamber", "role_proposal":"combat", "clear_rect_cells":[113,5,22,18]},
    {"id":"lower_east_chamber", "role_proposal":"combat", "clear_rect_cells":[121,81,22,18]},
    {"id":"upper_west_gallery", "role_proposal":"mining", "clear_rect_cells":[89,5,18,14]},
    {"id":"lower_west_gallery", "role_proposal":"mining", "clear_rect_cells":[23,83,18,14]},
    {"id":"east_combat_hall", "role_proposal":"combat", "clear_rect_cells":[122,40,24,16]},
    {"id":"west_combat_hall", "role_proposal":"combat", "clear_rect_cells":[76,60,22,16]},
]

floor = set()
def rectangle(x0,y0,x1,y1):
    floor.update((x,y) for y in range(y0,y1) for x in range(x0,x1)
                 if 0 <= x < SIZE[0] and 0 <= y < SIZE[1])
def corridor(points, width):
    assert width % 2 == 0
    half = width // 2
    for a,b in zip(points,points[1:]):
        assert a[0] == b[0] or a[1] == b[1]
        rectangle(min(a[0],b[0])-half,min(a[1],b[1])-half,
                  max(a[0],b[0])+half,max(a[1],b[1])+half)
corridor(MAIN,6)
for branch in BRANCHES:
    corridor(branch["points"],4)
for room in ROOMS:
    x,y,w,h = room["clear_rect_cells"]
    rectangle(x,y,x+w,y+h)
    # Extra one-cell perimeter space permits a chipped/chamfered rock edge
    # while retaining the entire declared clear interior rectangle.
    rectangle(x-1,y,x+w+1,y+h)
    rectangle(x,y-1,x+w,y+h+1)
    assert all((cx,cy) in floor for cy in range(y,y+h) for cx in range(x,x+w))
    room["clear_rect_world_pixels"] = [v*CELL for v in (x,y,w,h)]

start = (190,64)
reached = {start}
pending = deque([start])
while pending:
    x,y = pending.popleft()
    for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
        pt = (x+dx,y+dy)
        if pt in floor and pt not in reached:
            reached.add(pt)
            pending.append(pt)
assert reached == floor, (len(reached),len(floor))
assert (16,24) in reached

# Each tested cut crosses only the main route. It must separate the eastern
# start from the western terminal, proving sidelines do not skip progression.
gates = [("early", {(162,y) for y in range(60,68)}),
         ("middle", {(110,y) for y in range(44,52)}),
         ("late", {(58,y) for y in range(36,44)})]
for name,cut in gates:
    seen={start}; q=deque([start])
    while q:
        x,y=q.popleft()
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
            pt=(x+dx,y+dy)
            if pt in floor and pt not in cut and pt not in seen:
                seen.add(pt); q.append(pt)
    assert (16,24) not in seen, name+" has a progression bypass"

width,height = (v*CELL for v in SIZE)
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
     f'<rect width="{width}" height="{height}" fill="#0b1012"/>', '<g fill="#bc9b6d">']
for y in range(SIZE[1]):
    xs=sorted(x for x,cy in floor if cy==y)
    if not xs: continue
    begin=last=xs[0]
    for x in xs[1:]+[SIZE[0]+1]:
        if x == last+1:
            last=x
            continue
        svg.append(f'<rect x="{begin*CELL}" y="{y*CELL}" width="{(last-begin+1)*CELL}" height="32"/>')
        begin=last=x
svg+=['</g>','</svg>']
(OUT/'tile-guide-v3.svg').write_text('\n'.join(svg)+'\n',encoding='utf-8')
contract={"schema":1,"status":"tile-authored layout proposal; no installed scene or physical certification",
          "gameplay_cell_pixels":CELL,"gameplay_grid_origin":[0,0],"actor_body_pixels":[24,24],
          "world_size_cells":SIZE,"world_size_pixels":[width,height],
          "main_width_cells":6,"side_width_cells":4,"minimum_planned_choke_cells":4,
          "main_route_cells":MAIN,"branches":BRANCHES,"rooms":ROOMS,
          "planning_checks":{"floor_cells":len(floor),"cardinal_reachable_cells":len(reached),
             "declared_clear_room_rectangles_present":True,"progression_cut_gates":3},
          "preview_policy":"Generated overview may be downscaled for viewing. It is not a runtime texture to upscale; actual terrain and props require native art and the actual-scene worldbuilding gate after image approval.",
          "native_wall_review_note":"West combat hall and adjacent main leg leave a two-cell/64px rock band at x99-100,y60-64. Native wall silhouettes must be checked here; no universal96px rock-separation pass is claimed.",
          "background":"Keep existing dark rock/void; accidental background-removal request was canceled."}
(OUT/'tile-layout-v3.json').write_text(json.dumps(contract,indent=2)+'\n',encoding='utf-8')
print(json.dumps({"world_cells":SIZE,"world_pixels":[width,height],"connected_floor_cells":len(floor),
                  "rooms":[[r['id'],r['clear_rect_cells'][2:]] for r in ROOMS],"progression_gates_passed":3}))
