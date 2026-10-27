"""Assemble Bracken Mine authored geometry and canonical ore placements.

All coordinates were traced by a human-guided visual review of approved
cave-base-v1.png at native 1536x1024. This tool never samples image colors.
Run from any directory: python tools/build_bracken_mine_geometry.py
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot_client/Assets/Maps/BrackenMine"
SCENE = ROOT / "godot_client/scenes/BrackenMineContent.tscn"
WRAPPER = ROOT / "godot_client/scenes/BrackenMine.tscn"

# Continuous floor boundary, starting at the left edge of the south entrance,
# following its illustrated floor-side rock edges around all four alcoves.
FLOOR = [
(704,1024),(700,982),(704,957),(694,930),(692,900),(688,870),(686,838),
(665,820),(653,798),(631,787),(617,765),(592,756),(576,737),(551,729),
(536,709),(509,704),(492,685),(471,681),(455,658),(453,629),(438,603),
(422,588),(405,574),(382,575),(359,586),(334,589),(310,607),(281,610),
(254,610),(229,610),(205,602),(177,603),(152,589),(126,584),(107,570),
(88,565),(76,547),(60,533),(55,512),(45,497),(61,476),(70,454),
(79,437),(91,416),(110,404),(128,416),(147,428),(169,438),(196,441),
(220,446),(246,447),(269,456),(293,453),(319,457),(342,452),(364,458),
(384,449),(407,456),(430,465),(449,471),(469,466),(486,456),(502,442),
(514,425),(513,408),(500,394),(494,378),(481,365),(467,352),(446,348),
(426,342),(408,331),(393,310),(375,302),(363,289),(340,283),(318,277),
(299,271),(278,254),(254,250),(236,243),(214,239),(200,225),(180,227),
(166,218),(147,221),(128,212),(122,198),(139,191),(159,188),(177,181),
(186,165),(210,153),(234,145),(256,136),(282,129),(308,128),(332,132),
(359,142),(381,149),(409,158),(431,165),(451,178),(468,191),(481,208),
(501,224),(523,238),(545,248),(569,257),(591,260),(618,268),(641,264),
(663,256),(684,245),(710,240),(735,230),(765,227),(789,219),(812,218),
(839,227),(858,226),(883,230),(901,244),(921,257),(941,268),(966,277),
(990,284),(1014,282),(1044,273),(1072,270),(1098,264),(1121,262),
(1141,250),(1162,247),(1184,235),(1205,227),(1227,217),(1247,217),
(1269,219),(1289,229),(1309,239),(1330,244),(1345,256),(1362,264),
(1380,269),(1396,280),(1416,288),(1433,300),(1449,319),(1450,336),
(1432,348),(1412,352),(1396,356),(1377,351),(1359,354),(1345,343),
(1322,347),(1303,338),(1286,336),(1267,332),(1249,329),(1232,328),
(1212,332),(1195,338),(1180,352),(1172,369),(1172,386),(1181,400),
(1193,412),(1209,424),(1225,437),(1241,455),(1253,473),(1250,491),
(1232,505),(1225,519),(1213,529),(1214,545),(1230,557),(1249,565),
(1270,567),(1292,569),(1310,564),(1327,569),(1344,565),(1361,573),
(1379,579),(1393,589),(1413,595),(1427,610),(1431,629),(1445,642),
(1457,661),(1461,679),(1455,699),(1436,710),(1423,725),(1399,733),
(1373,742),(1350,742),(1328,742),(1306,737),(1283,731),(1261,726),
(1239,718),(1220,708),(1200,699),(1183,686),(1163,681),(1144,671),
(1125,657),(1109,652),(1094,638),(1087,620),(1092,603),(1084,590),
(1070,594),(1056,610),(1040,627),(1019,641),(999,659),(978,678),
(958,697),(939,712),(918,735),(905,754),(894,773),(881,791),
(870,807),(861,830),(853,849),(848,872),(851,893),(858,915),
(872,939),(880,962),(884,986),(892,1004),(900,1024),
]
ISLAND = [
(776,285),(797,289),(811,299),(832,304),(848,322),(872,328),
(887,343),(910,347),(929,358),(948,365),(963,379),(987,386),
(1003,406),(1021,417),(1032,439),(1029,459),(1015,479),(994,489),
(978,509),(950,519),(932,537),(905,546),(883,559),(858,568),
(838,580),(815,576),(793,581),(772,576),(752,580),(732,571),
(713,559),(697,540),(682,526),(667,515),(646,502),(650,480),
(660,462),(667,439),(678,418),(688,393),(706,375),(717,351),
(737,337),(748,317),(754,300),
]
POOL = [(958,153),(982,152),(1005,151),(1033,151),(1059,160),
(1084,169),(1109,182),(1129,207),(1149,225),(1144,243),(1116,253),
(1092,254),(1060,263),(1032,268),(1006,270),(983,268),(962,257),
(943,244),(928,224),(928,202),(940,184),(948,168)]
# The user's annotated image replaces the earlier proposed placement roster.
# A dot is the visible rock center, not its foot anchor. Integer positions keep
# native pixels crisp; the movement/AoE lattice remains independently fixed.
MARKERS = json.loads((OUTPUT / "ore-markers.json").read_text(encoding="utf-8"))["markers"]
ORES = [(m["id"], m["ore_id"],
    (m["dot_center"][0] + m["adjustment"][0],
     m["dot_center"][1] + m["adjustment"][1] + 24)) for m in MARKERS]
PROBES = [
("EntranceApproach", (768,896)),("SouthJunction", (784,720)),
("WestLoop", (560,496)),("NorthLoop", (720,272)),
("EastLoop", (1104,464)),("SouthLoop", (816,624)),
("NorthWestAlcove", (304,208)),("WestAlcove", (240,544)),
("NorthEastAlcove", (1280,304)),("SouthEastAlcove", (1328,688)),
]
def approach(name, position):
    marker = next(m for m in MARKERS if m["id"] == name)
    return tuple(marker["approach"])

def packed(points):
    return "PackedVector2Array(" + ", ".join(str(v) for p in points for v in p) + ")"

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    layout = {
        "schema":1,"area":"Bracken Mine","world_size":[1536,1024],
        "gameplay_grid_origin":[0,0],"gameplay_cell_pixels":32,"actor_body_pixels":[24,24],
        "geometry_source":"Hand-authored floor-side rock outlines reviewed against approved cave-base-v1.png; never inferred from pixel colors.",
        "collision_policy":"Solid exterior complement plus central rock island, pool, extracted prop bases and native ore paired bases. Map edges seal the entrance at world bounds.",
        "floor_boundary":FLOOR,
        "exclusions":[{"name":"CentralRockIsland","polygon":ISLAND},{"name":"NorthPool","polygon":POOL}],
        "arrival":[768,928],"exit_approach":[768,896],
        "probes":[{"name":n,"position":p} for n,p in PROBES] + [{"name":n+"Approach","position":approach(n,p)} for n,ore,p in ORES],
        "ores":[{"name":n,"user_marker_id":n,"ore_id":ore,"position":p,"approach":approach(n,p),"scale":[1,1],"role":"visual prop with canonical physical bases; no mining rules"} for n,ore,p in ORES],
        "ore_placement_status":"Installed canonical scene placements; gameplay mining definitions remain unmodified.",
        "ore_placement_policy":"Only the user's fifteen annotated locations and ore colors. Visible centers follow dots; only documented conflicts receive minimum inward corrections. Full sprite alpha clears walls and other props; each physical base has a reachable adjacent approach. No arbitrary near-wall thresholds or ore-count balancing.",
    }
    (OUTPUT / "layout.json").write_text(json.dumps(layout,indent=2)+"\n",encoding="utf-8")
    # Floor meets the southern world edge. Its complement therefore has one
    # simple contour, without holes or image-derived grid cells. Godot decomposes
    # this solid concave polygon into convex collision pieces at import/runtime.
    exterior = [(0,0),(1536,0),(1536,1024)] + list(reversed(FLOOR)) + [(0,1024)]
    text = ['[gd_scene load_steps=6 format=3]', '',
        '[ext_resource type="PackedScene" path="res://scenes/BrackenMineArtwork.tscn" id="1_art"]']
    names = {"copper":"CopperOreFull","tin":"TinOreFull","iron":"IronOreFull","coal":"CoalFull"}
    for i,(ore,name) in enumerate(names.items(),2):
        text.append(f'[ext_resource type="PackedScene" path="res://scenes/MapProps/OreNodes/{name}.tscn" id="{i}_{ore}"]')
    text += ['', '[node name="BrackenMineContent" type="Node2D"]','y_sort_enabled = true','texture_filter = 1',
        'metadata/gameplay_grid_origin = Vector2(0, 0)', '',
        '[node name="BrackenMineArtwork" parent="." instance=ExtResource("1_art")]', '',
        '[node name="Collision" type="StaticBody2D" parent="." groups=["world_solid"]]',
        'collision_layer = 1','collision_mask = 0']
    for name,poly in [("ExteriorRock",exterior),("CentralRockIsland",ISLAND),("NorthPool",POOL),
        ("NorthBounds",[(-64,-64),(1600,-64),(1600,0),(-64,0)]),
        ("SouthBounds",[(-64,1024),(1600,1024),(1600,1088),(-64,1088)]),
        ("WestBounds",[(-64,0),(0,0),(0,1024),(-64,1024)]),
        ("EastBounds",[(1536,0),(1600,0),(1600,1024),(1536,1024)])]:
        text += ['',f'[node name="{name}" type="CollisionPolygon2D" parent="Collision"]',f'polygon = {packed(poly)}']
    # Direct ore children share the wrapper's y-sort through this y-sorted root.
    for name,ore,position in ORES:
        index = list(names).index(ore)+2
        text += ['',f'[node name="{name}" parent="." instance=ExtResource("{index}_{ore}")]',
            f'position = Vector2({position[0]}, {position[1]})']
    text += ['', '[node name="GridProbes" type="Node2D" parent="."]']
    for name,position in PROBES:
        text += ['',f'[node name="{name}" type="Marker2D" parent="GridProbes"]',
            f'position = Vector2({position[0]}, {position[1]})']
    for name,ore,position in ORES:
        point = approach(name,position)
        text += ['',f'[node name="{name}Approach" type="Marker2D" parent="GridProbes"]',
            f'position = Vector2({point[0]}, {point[1]})']
    SCENE.write_text("\n".join(text)+"\n",encoding="utf-8")
    # Runtime grid adoption reads the wrapper's probes. Regenerate that one
    # bounded block with content so moving a rock cannot leave stale routes.
    wrapper = WRAPPER.read_text(encoding="utf-8")
    start = wrapper.index('[node name="GridProbes" type="Node2D" parent="."]')
    end = wrapper.index('[node name="Combat" type="Node2D" parent="."]', start)
    probes = ['[node name="GridProbes" type="Node2D" parent="."]']
    for probe in layout["probes"]:
        x, y = probe["position"]
        probes += ['', f'[node name="{probe["name"]}" type="Marker2D" parent="GridProbes"]',
            f'position = Vector2({x}, {y})']
    WRAPPER.write_text(wrapper[:start] + "\n".join(probes) + "\n\n" + wrapper[end:], encoding="utf-8")
    print(f"Built authored mine geometry, {len(PROBES)+len(ORES)} probes and {len(ORES)} canonical ore instances.")

if __name__ == "__main__":
    main()
