"""Build exact pixel frames from one whole PixelLab stone. No image rescaling.

The stone translates behind a horizontal floor occlusion plane. Its shape and
palette never warp. Red crack lines and six tiny chips are hand-authored VFX,
not replacement map artwork. Run with py -3.13 <this file> after source selection.
"""
from pathlib import Path
import hashlib
import json
import math
import re
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SIZE = (48, 64)
ANCHOR = (24, 52)
TICK_CONFIG = ROOT/'godot_client/scripts/game_tick_config.gd'
TICK_SECONDS = float(re.search(r'TICK_DURATION_SECONDS\s*:=\s*([0-9.]+)', TICK_CONFIG.read_text(encoding='utf-8'))[1])
STEPS_PER_TICK = 30
FRAME_MS = round(TICK_SECONDS * 1000 / STEPS_PER_TICK)
assert FRAME_MS * STEPS_PER_TICK == round(TICK_SECONDS * 1000)

def height_at_step(step):
    if step == STEPS_PER_TICK:
        return 51
    if step == 0 or step >= STEPS_PER_TICK*2:
        return 0
    progress = (step if step < STEPS_PER_TICK else step-STEPS_PER_TICK)/STEPS_PER_TICK
    value = 51*0.5*(1-math.cos(math.pi*progress) if step < STEPS_PER_TICK else 1+math.cos(math.pi*progress))
    return max(1,min(50,math.floor(value+0.500001)))

HEIGHTS = [height_at_step(i) for i in range(STEPS_PER_TICK*2+6)]
CRACKS = [
    [(24,56),(19,53),(16,54),(11,50)],
    [(24,56),(26,51),(25,47),(29,43)],
    [(24,56),(30,54),(33,56),(38,52)],
    [(24,56),(20,58),(19,61),(13,62)],
    [(24,56),(29,59),(34,59),(37,62)],
    [(17,54),(14,57),(10,57)],
    [(30,54),(33,49),(36,48)],
]

def cracks(stage, fade=1.0):
    image = Image.new('RGBA', SIZE)
    draw = ImageDraw.Draw(image)
    colors = [(180,24,34),(210,32,43),(235,44,54),(255,61,66)]
    color = tuple(round(c*fade) for c in colors[stage])+(255,)
    for path in CRACKS:
        count = len(path)
        shifted=[(x,y+ANCHOR[1]-56) for x,y in path[:count]]
        draw.line(shifted, fill=(37,17,19,255), width=3)
        draw.line(shifted, fill=color, width=1)
    if stage >= 2:
        for x,y in [(19,53),(26,51),(30,54),(20,58),(29,59)]:
            draw.point((x,y+ANCHOR[1]-56), fill=(255,103,95,255) if stage==3 else color)
    return image

def build():
    source = Image.open(HERE/'source-selected.png').convert('RGBA')
    assert source.size == SIZE
    bbox = source.getbbox()
    assert bbox and bbox[2]-bbox[0] <= 32, ('Spike must fit its cell without shrinking', bbox)
    # Whole source translation only; no segmentation, stretch or interpolation.
    center = (bbox[0]+bbox[2]-1)//2
    dx,dy = ANCHOR[0]-center, ANCHOR[1]-(bbox[3]-1)
    master = Image.new('RGBA', SIZE)
    master.paste(source,(dx,dy))
    assert master.getbbox()[0]>0 and master.getbbox()[2]<SIZE[0]
    assert bbox[3]-bbox[1] <= 53, 'Need a complete native spike with margin'
    master.save(HERE/'master-spike.png')
    max_height = ANCHOR[1]-master.getbbox()[1]+1
    frames = [cracks(stage) for stage in range(4)]
    for index,height in enumerate(HEIGHTS):
        cleanup_start = STEPS_PER_TICK*2
        fade = 1.0 if index < cleanup_start else (len(HEIGHTS)-index)/7
        frame = cracks(3,fade)
        if height:
            layer = Image.new('RGBA',SIZE)
            layer.paste(master,(0,max_height-height))
            # Flat floor contact is deliberate: the intact stone is underneath.
            layer.paste((0,0,0,0),(0,ANCHOR[1]+1,SIZE[0],SIZE[1]))
        # Small six-piece debris burst, confined to the same cell. Disappears
        # by cleanup; these are authored impact chips, not orphan source pixels.
        if 3 <= index <= 20:
            draw=ImageDraw.Draw(frame)
            chip_step=min(6,index//3)
            for number,(sx,sy) in enumerate([(-8,-3),(9,-4),(-5,2),(7,3),(-12,0),(12,1)]):
                x=24+sx+(chip_step//3 if sx>0 else -(chip_step//3))
                y=ANCHOR[1]+sy-max(0,4-abs(chip_step-3)*2)
                draw.rectangle((x,y,x+1,y+1),fill=(161,146,120,255) if number%2 else (84,72,58,255))
        if height:
            frame.alpha_composite(layer)
        frames.append(frame)
    frames.append(Image.new('RGBA',SIZE))
    frame_dir=HERE/'frames'
    frame_dir.mkdir(exist_ok=True)
    atlas=Image.new('RGBA',(SIZE[0]*len(frames),SIZE[1]))
    for i,frame in enumerate(frames):
        frame.save(frame_dir/f'{i:02}.png')
        atlas.paste(frame,(i*SIZE[0],0))
    atlas.save(HERE/'spike-atlas.png')
    runtime=ROOT/'godot_client/Assets/Effects/TitanPhysicalSpike'
    runtime.mkdir(parents=True,exist_ok=True)
    atlas.save(runtime/'spike-atlas.png')
    metadata={
        'schema_version':1,'asset_id':'titan_physical_spike_v1',
        'native_canvas':list(SIZE),'ground_anchor':list(ANCHOR),
        'world_pixels_per_source_pixel':1,'ground_footprint_size':[32,32],
        'warning_color':'red','warning_frames':[0,1,2,3],
        'revision':'tick-paced-v2','tick_duration_ms':round(TICK_SECONDS*1000),
        'tick_config':'godot_client/scripts/game_tick_config.gd',
        'warning_duration_control':'combat engine; default two combat ticks',
        'default_warning_ms':round(TICK_SECONDS*2000),
        'motion_samples_per_tick':STEPS_PER_TICK,
        'strike_frames':list(range(4,4+len(HEIGHTS))),'strike_durations_ms':[FRAME_MS]*len(HEIGHTS),
        'protrusion_height_px':HEIGHTS,'peak_index':4+STEPS_PER_TICK,'peak_hold_ms':0,
        'first_retraction_frame':5+STEPS_PER_TICK,'rise_ms':round(TICK_SECONDS*1000),'fall_ms':round(TICK_SECONDS*1000),
        'spike_gone_after_contact_ms':round(TICK_SECONDS*2000),
        'complete_after_contact_ms':len(HEIGHTS)*FRAME_MS,'inactive_frame':4+len(HEIGHTS),
        'source_to_master_translation_px':[dx,dy],
        'source_sha256':hashlib.sha256((HERE/'source-selected.png').read_bytes()).hexdigest(),
        'atlas_sha256':hashlib.sha256((HERE/'spike-atlas.png').read_bytes()).hexdigest(),
        'generation':{'service':'PixelLab','model':'pro','job_id':'531dfe1b-6f27-4fb4-ba94-a17313f337ed','candidate_count':16,
                      'style_reference':'art_sources/characters/golem-titan-bound-v2/south.png'},
        'animation_method':'whole rigid stone translated vertically behind floor occlusion; no scaling, warping or cut body parts',
        'debris_reason':'six intentional two-pixel stone chips confined to affected cell during impact/retraction',
        'alpha_reason':'transparent background, source silhouette alpha preserved; warning drawn on native pixel grid',
        'artwork_approval':'candidate_pending_user_review','production_encounter_installation':'not_performed',
        'scope':'one reusable effect; no combat damage, balance, target selection or world placement changes',
    }
    (HERE/'manifest.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    # Pixel-exact sheet and preview for art review, no resampling of source art.
    columns=12
    rows=math.ceil(len(frames)/columns)
    sheet=Image.new('RGBA',(48*columns,64*rows),(38,35,33,255))
    for i,frame in enumerate(frames):
        sheet.alpha_composite(frame,((i%columns)*48,(i//columns)*64))
    sheet.resize((sheet.width*4,sheet.height*4),Image.Resampling.NEAREST).save(HERE/'contact-sheet-4x.png')
    durations=[round(TICK_SECONDS*500)]*4+[FRAME_MS]*len(HEIGHTS)+[480]
    previews=[]
    for frame in frames:
        bg=Image.new('RGBA',SIZE,(47,43,39,255)); bg.alpha_composite(frame)
        previews.append(bg.resize((192,256),Image.Resampling.NEAREST))
    previews[0].save(HERE/'single-spike-preview.webp',save_all=True,append_images=previews[1:],duration=durations,loop=0,lossless=True,method=6)
    print(json.dumps({'frames':len(frames),'source_bbox':bbox,'full_visible_height_px':max_height,'atlas':atlas.size,'status':'candidate'}))

if __name__ == '__main__':
    build()
