"""Package bounded linework restorations without changing gameplay geometry.

Raw imagegen edits and exact prompts live in the selected authoring directory.
The immutable approved original and reviewed foreground alpha remain authorities.
Only hard minimum-error cuts select pixels; no blended seam or generated physics.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
AREA = ROOT / 'godot_client/Assets/Maps/ValtherianMines'
DETAIL = AREA / 'Detail'
SCENE = ROOT / 'godot_client/scenes/ValtherianMinesContent.tscn'
SIZE = (8192, 4438)
SOURCE_SIZE = (1703, 924)
ORIGINAL_SHA = '8ddfeb0018110c36f3937592a09b378f61b9122d1d2f761eb4f6931dffedea90'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, data):
    Path(path).write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def fingerprint(scene):
    sections = re.split(r'(?=\[node )', scene)
    gameplay = [s for s in sections if s.startswith('[node ') and not
                ('name="ApprovedMap"' in s.split('\n')[0] or
                 'name="ApprovedForeground"' in s.split('\n')[0] or
                 'parent="ApprovedForeground' in s.split('\n')[0])]
    # All shape resources, collision nodes and every ore root transform are kept.
    resources = re.findall(r'\[sub_resource[^\n]*\n.*?(?=\n\[|\Z)', scene, re.S)
    return hashlib.sha256((''.join(resources) + ''.join(gameplay)).encode()).hexdigest()


def minimum_cut(cost):
    """Connected top-to-bottom path, changing at most one column per row."""
    h, w = cost.shape
    previous = cost[0].astype(np.float64)
    parents = np.zeros((h, w), dtype=np.int8)
    for y in range(1, h):
        candidates = np.stack((np.r_[np.inf, previous[:-1]], previous,
                               np.r_[previous[1:], np.inf]))
        choice = np.argmin(candidates, axis=0)
        parents[y] = choice - 1
        previous = candidates[choice, np.arange(w)] + cost[y]
    x = int(np.argmin(previous))
    result = np.empty(h, dtype=np.int32)
    result[-1] = x
    for y in range(h - 1, 0, -1):
        x += int(parents[y, x])
        result[y - 1] = x
    return result


def difference(a, b):
    d = a[:, :, :3].astype(np.float32) - b[:, :, :3].astype(np.float32)
    return np.sum(d * d, axis=2)


def registered_input(author, job, registrations):
    """Reproduce retained affine registration using only NumPy/Pillow."""
    registered = author / f"{job['id']}-registered.png"
    if registered.exists():
        return Image.open(registered).convert('RGBA')
    raw = np.array(Image.open(author / job.get('output',f"{job['id']}-detail.png")).convert('RGBA'))
    record = registrations.get(job['id'])
    if record:
        matrix = np.array(record['affine_source_to_generated'],dtype=np.float32)
        fx,fy = np.meshgrid(np.arange(raw.shape[1],dtype=np.float32),np.arange(raw.shape[0],dtype=np.float32))
        q = raw.shape[1]/job['rect'][2]
        mx = matrix[0,0]*fx+matrix[0,1]*fy+matrix[0,2]*q
        my = matrix[1,0]*fx+matrix[1,1]*fy+matrix[1,2]*q
        ix = np.clip(np.rint(mx).astype(int),0,raw.shape[1]-1)
        iy = np.clip(np.rint(my).astype(int),0,raw.shape[0]-1)
        raw = raw[iy,ix]
        expected = record.get('registered_rgb_sha256')
        if expected:
            assert hashlib.sha256(raw[:,:,:3].tobytes()).hexdigest()==expected,job['id']+' registration differs'
    return Image.fromarray(raw)


def stitch(author, jobs, source_path):
    source = Image.open(source_path).convert('RGBA')
    registration_path = author/'registration-report.json'
    registrations = {r['id']:r for r in json.loads(registration_path.read_text())} if registration_path.exists() else {}
    master = np.array(source.resize(SIZE, Image.Resampling.NEAREST))
    coverage = np.zeros((SIZE[1], SIZE[0]), dtype=bool)
    seams = []
    last_bottom = 0
    for r in sorted({j['row'] for j in jobs}):
        selected = [j for j in jobs if j['row'] == r]
        y0 = round(selected[0]['rect'][1] * SIZE[1] / SOURCE_SIZE[1])
        y1 = round((selected[0]['rect'][1] + 260) * SIZE[1] / SOURCE_SIZE[1])
        height = y1 - y0
        row = master[y0:y1].copy()
        row_coverage = np.zeros((height, SIZE[0]), dtype=bool)
        right = 0
        for job in sorted(selected, key=lambda j: j['col']):
            x, y, w, h = job['rect']
            x0, x1 = round(x * SIZE[0] / SOURCE_SIZE[0]), round((x + w) * SIZE[0] / SOURCE_SIZE[0])
            image = registered_input(author,job,registrations)
            assert image.width >= x1-x0 and image.height >= height, 'Never enlarge generated source'
            tile = np.array(image.resize((x1-x0, height), Image.Resampling.NEAREST))
            overlap = max(0, right - x0)
            use = np.ones((height, x1-x0), dtype=bool)
            if overlap:
                cost = difference(row[:, x0:x0+overlap], tile[:, :overlap])
                cut = minimum_cut(cost)
                use[:, :overlap] = np.arange(overlap)[None, :] >= cut[:, None]
                use[:, :overlap] |= ~row_coverage[:, x0:x0+overlap]
                seams.append({'axis':'vertical', 'job':job['id'], 'detail_origin':[x0,y0], 'detail_overlap':overlap,
                              'path_min':int(cut.min()), 'path_max':int(cut.max())})
            view = row[:, x0:x1]
            view[use] = tile[use]
            row_coverage[:, x0:x1] = True
            right = x1
        overlap = max(0, last_bottom-y0)
        use = row_coverage.copy()
        if overlap:
            cost = difference(master[y0:y0+overlap], row[:overlap]).T
            both = (coverage[y0:y0+overlap] & row_coverage[:overlap]).T
            cost[~both] = 0
            cut = minimum_cut(cost)
            retain = np.arange(overlap)[:, None] < cut[None, :]
            retain &= coverage[y0:y0+overlap]
            use[:overlap] &= ~retain
            seams.append({'axis':'horizontal', 'row':r,'detail_origin':[0,y0], 'detail_overlap':overlap,
                          'path_min':int(cut.min()), 'path_max':int(cut.max())})
        view = master[y0:y1]
        view[use] = row[use]
        coverage[y0:y1] |= row_coverage
        last_bottom = y1
    original = np.array(source.resize(SIZE, Image.Resampling.NEAREST))
    uncovered = (~coverage) & (original[:, :, :3].max(axis=2) > 45)
    assert not np.any(uncovered), 'Visible source left unrestored'
    Image.fromarray(master).save(DETAIL / 'master-linework.png')
    Image.fromarray(master).resize(SOURCE_SIZE, Image.Resampling.NEAREST).save(author / 'whole-map-registration.png')
    return master, seams, int(np.sum(~coverage))


def foreground(master):
    old = json.loads((AREA/'Approved/foreground-bands.json').read_text())
    alpha = np.array(Image.open(AREA/'Approved/foreground.png').convert('RGBA'))[:, :, 3]
    records = []
    pieces = []
    shelf_x = shelf_y = shelf_h = 0
    for band in old['bands']:
        x,y,w,h = band['source_rect']
        ax,ay,_,_ = band['atlas_rect']
        # Global-coordinate nearest sampling retains the exact reviewed alpha geometry.
        x0 = int(np.ceil(x * SIZE[0] / SOURCE_SIZE[0]))
        x1 = int(np.ceil((x+w) * SIZE[0] / SOURCE_SIZE[0]))
        y0 = int(np.ceil(y * SIZE[1] / SOURCE_SIZE[1]))
        y1 = int(np.ceil((y+h) * SIZE[1] / SOURCE_SIZE[1]))
        sx = np.floor(np.arange(x0,x1)*SOURCE_SIZE[0]/SIZE[0]).astype(int)-x+ax
        sy = np.floor(np.arange(y0,y1)*SOURCE_SIZE[1]/SIZE[1]).astype(int)-y+ay
        pixels = master[y0:y1,x0:x1].copy()
        pixels[:,:,3] = alpha[sy[:,None],sx[None,:]]
        width,height = x1-x0,y1-y0
        if shelf_x+width > SIZE[0]:
            shelf_x = 0
            shelf_y += shelf_h+2
            shelf_h = 0
        records.append({**band,'detail_source_rect':[x0,y0,width,height],
                        'atlas_rect':[shelf_x,shelf_y,width,height]})
        pieces.append(pixels)
        shelf_x += width+2
        shelf_h = max(shelf_h,height)
    atlas = np.zeros((shelf_y+shelf_h,SIZE[0],4), dtype=np.uint8)
    mismatch = 0
    for b,pixels in zip(records,pieces):
        x,y,w,h = b['atlas_rect']
        atlas[y:y+h,x:x+w] = pixels
        dx,dy,_,_ = b['detail_source_rect']
        visible = pixels[:,:,3]>0
        mismatch += int(np.sum(np.any(pixels[:,:,:3]!=master[dy:dy+h,dx:dx+w,:3],axis=2)&visible))
    assert mismatch == 0
    Image.fromarray(atlas).save(DETAIL/'foreground.png')
    data = {'schema':1,'source':'res://Assets/Maps/ValtherianMines/Detail/master-linework.png',
            'source_size':list(SIZE),'atlas_size':[atlas.shape[1],atlas.shape[0]],
            'alpha_authority_sha256':sha(AREA/'Approved/foreground.png'),
            'bands':records,'source_rgb_mismatches':mismatch,
            'method':'Same92bands, sort feet and global-coordinate alpha geometry; RGB copied exactly from new master.'}
    write(DETAIL/'foreground-bands.json',data)
    return records


def bind(records):
    scene = SCENE.read_text(encoding='utf-8')
    before = fingerprint(scene)
    # Existing node names, physics and ore blocks remain byte-for-byte identical.
    scene = scene.replace('res://Assets/Maps/ValtherianMines/Approved/approved-map-v3.png',
                          'res://Assets/Maps/ValtherianMines/Detail/master-linework.png')
    scene = scene.replace('res://Assets/Maps/ValtherianMines/Approved/foreground.png',
                          'res://Assets/Maps/ValtherianMines/Detail/foreground.png')
    if 'id="8_detail_palette"' not in scene:
        scene = scene.replace('\n[sub_resource ', '\n[ext_resource type="Material" path="res://Assets/Maps/ValtherianMines/Detail/CrispMine.tres" id="8_detail_palette"]\n\n[sub_resource ',1)
        scene = re.sub(r'load_steps=(\d+)',lambda m:f'load_steps={int(m[1])+1}',scene,count=1)
    sections = re.split(r'(?=\[node )',scene)
    for i,s in enumerate(sections):
        header = s.split('\n')[0]
        if 'name="ApprovedMap"' in header:
            s = re.sub(r'scale = Vector2\([^\n]*',f'scale = Vector2(0.75, {3328/SIZE[1]:.10f})',s)
            if 'material = ' not in s:
                s = s.replace('z_index = ', 'material = ExtResource("8_detail_palette")\nz_index = ')
        elif 'name="ExactPixels"' in header and 'parent="ApprovedForeground/' in header:
            name = re.search(r'parent="ApprovedForeground/([^"]+)"',header)[1]
            band = next(b for b in records if b['name']==name)
            x,y,_,_ = band['detail_source_rect']
            ax,ay,w,h = band['atlas_rect']
            s = re.sub(r'scale = Vector2\([^\n]*',f'scale = Vector2(0.75, {3328/SIZE[1]:.10f})',s)
            s = re.sub(r'offset = Vector2\([^\n]*',f'offset = Vector2({x}, {y})',s)
            s = re.sub(r'region_rect = Rect2\([^\n]*',f'region_rect = Rect2({ax}, {ay}, {w}, {h})',s)
            if 'material = ' not in s:
                s = s.replace('texture_filter = ', 'material = ExtResource("8_detail_palette")\ntexture_filter = ')
        sections[i] = s
    result = ''.join(sections)
    after = fingerprint(result)
    assert before == after, 'Gameplay or sort-foot structure changed'
    SCENE.write_text(result,encoding='utf-8')
    return before


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--authoring',type=Path,default=ROOT/'art_sources/valtherian-mines/detail-v1')
    parser.add_argument('--source',type=Path,default=AREA/'Approved/approved-map-v3.png')
    parser.add_argument('--bind',action='store_true')
    args = parser.parse_args()
    assert sha(args.source) == ORIGINAL_SHA
    DETAIL.mkdir(exist_ok=True)
    jobs = json.loads((args.authoring/'jobs.json').read_text())
    master,seams,dark = stitch(args.authoring,jobs,args.source)
    records = foreground(master)
    metadata = {'schema':1,'status':'installed candidate; full visual review separate' if args.bind else 'packaged candidate; not yet installed',
                'source_sha256':ORIGINAL_SHA,'native_size':list(SIZE),'world_size':[6144,3328],
                'world_pixels_per_texel':[.75,3328/SIZE[1]],'anchor':[0,0],
                'generator':'built-in imagegen; high-resolution linework first; nearest reduction once',
                'builtin_generations':len(jobs)+1,'restored_regions':len(jobs),
                'unrestored_visible_source_pixels':0,'retained_original_dark_texels':dark,
                'foreground_bands':len(records),'foreground_rgb_mismatches':0,
                'seams':seams,'master_sha256':sha(DETAIL/'master-linework.png'),
                'region_sources':[{'id':j['id'],'rect':j['rect'],
                                  'detail_sha256':sha(args.authoring/j.get('output',f"{j['id']}-detail.png")),
                                  'registered_sha256':sha(args.authoring/f"{j['id']}-registered.png") if (args.authoring/f"{j['id']}-registered.png").exists() else None} for j in jobs]}
    registration = args.authoring/'registration-report.json'
    if registration.exists():
        metadata['registration'] = json.loads(registration.read_text())
    provenance = args.authoring/'provenance.json'
    if provenance.exists():
        raw = json.loads(provenance.read_text())
        metadata['imagegen_outputs'] = [{'id':j['id'],'generated_file':j.get('generated_file',j.get('generated','')).replace('\\','/').split('/')[-1],
                                        'added_open_edge_constraint':j['edge_constraint']} for j in raw['regions']]
    prompt = args.authoring/'restoration.prompt.txt'
    if prompt.exists():
        (DETAIL/'restoration.prompt.txt').write_bytes(prompt.read_bytes())
        metadata['prompt_sha256'] = sha(prompt)
    if args.bind:
        metadata['gameplay_scene_fingerprint'] = bind(records)
    write(DETAIL/'manifest.json',metadata)
    print(json.dumps({k:v for k,v in metadata.items() if k not in ('seams','region_sources','registration','imagegen_outputs')}))


if __name__=='__main__':
    main()
