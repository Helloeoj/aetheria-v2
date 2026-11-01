"""Independent source/atlas contract checks. Prints compact results; no writes."""
from pathlib import Path
from PIL import Image
import hashlib
import json
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def verify():
    checks=0
    def check(ok,label):
        nonlocal checks
        assert ok,label
        checks+=1
    manifest=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
    atlas=Image.open(HERE/'spike-atlas.png').convert('RGBA')
    runtime=ROOT/'godot_client/Assets/Effects/TitanPhysicalSpike/spike-atlas.png'
    frame_count=manifest['inactive_frame']+1
    check(atlas.size==(48*frame_count,64) and frame_count==71,'71 native 48x64 frames')
    check(runtime.read_bytes()==(HERE/'spike-atlas.png').read_bytes(),'runtime atlas exact source bytes')
    check(hashlib.sha256(runtime.read_bytes()).hexdigest()==manifest['atlas_sha256'],'manifest atlas hash')
    frames=[]
    for i in range(frame_count):
        im=Image.open(HERE/f'frames/{i:02}.png').convert('RGBA')
        frames.append(im)
        check(im.size==(48,64),f'frame {i} native size')
        check(im.tobytes()==atlas.crop((i*48,0,(i+1)*48,64)).tobytes(),f'frame {i} atlas roundtrip')
        check(set(im.getchannel('A').getdata())<={0,255},f'frame {i} binary pixel alpha')
        box=im.getbbox()
        check(box is None or (box[0]>=8 and box[2]<=40 and box[3]<=64),f'frame {i} width inside 32px cell')
    for i in range(4):
        visible=[p for p in frames[i].getdata() if p[3]]
        check(all(r>g and r>b for r,g,b,a in visible),f'warning {i} red physical cue')
        check(frames[i].getbbox()[1]>=36,f'warning {i} entirely on ground cell')
    check(frames[-1].getbbox() is None,'final frame fully disappears')
    heights=manifest['protrusion_height_px']
    check(len(heights)==66 and heights.count(51)==1 and heights[30]==51,'one peak with immediate retraction')
    check(all(heights[i]<=heights[i+1] for i in range(30)) and all(heights[i]>=heights[i+1] for i in range(30,65)),'rise and fall are monotonic')
    check(max(abs(b-a) for a,b in zip(heights,heights[1:]))<=3,'small eased native motion steps')
    check(manifest['peak_hold_ms']==0 and manifest['rise_ms']==manifest['fall_ms']==manifest['tick_duration_ms']==600,'one whole combat tick per phase, no added peak dwell')
    check(sum(manifest['strike_durations_ms'][:60])==1200 and heights[60]==0,'stone returns below floor after two ticks')
    master=Image.open(HERE/'master-spike.png').convert('RGBA')
    source=Image.open(HERE/'source-selected.png').convert('RGBA')
    dx,dy=manifest['source_to_master_translation_px']
    for y in range(64):
        for x in range(48):
            if source.getpixel((x,y))[3]:
                check(master.getpixel((x+dx,y+dy))==source.getpixel((x,y)),'whole stone source preserved without resampling')
    for y in range(64):
        for x in range(48):
            p=master.getpixel((x,y))
            if p[3]:
                check(frames[manifest['peak_index']].getpixel((x,y))==p,'full peak preserves whole master silhouette and stone pixels')
    for index,height in enumerate(heights):
        if not height:
            continue
        for y in range(64):
            target_y=y+51-height
            if target_y>52:
                continue
            for x in range(48):
                pixel=master.getpixel((x,y))
                if pixel[3]:
                    check(frames[4+index].getpixel((x,target_y))==pixel,'each in-between frame preserves whole translated source pixels')
    source_rel='art_sources/characters/golem-titan-bound-v2'
    # Authoritative approved revision, independent of whatever branch the shared checkout is on.
    for suffix in ['south.png']+[f'shockwave_slam/frames/{i:02}.png' for i in range(18)]:
        path=f'{source_rel}/{suffix}'
        old=subprocess.check_output(['git','show',f'beccdcb20c0c3b015f1e14ce6017d61564ded9c5:{path}'],cwd=ROOT)
        check(old==(ROOT/path).read_bytes(),f'approved Titan unchanged: {suffix}')
    settings=runtime.with_suffix('.png.import').read_text(encoding='utf-8')
    check('compress/mode=0' in settings and 'mipmaps/generate=false' in settings,'lossless import without mipmaps')
    print(json.dumps({'checks':checks,'failures':0,'artwork_status':manifest['artwork_approval'],'production_placement':'not_performed'}))

if __name__=='__main__':
    verify()
