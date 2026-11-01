"""Lossless previews from actual Godot captures, preserving all sample times."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw

def pack(render: Path, output: Path):
    output.mkdir(parents=True,exist_ok=True)
    report_path=render/'godot-animation-review.json'
    report=json.loads(report_path.read_text(encoding='utf-8'))
    assert not report['failures'] and len(report['effect_cells'])==10
    assert len({tuple(c) for c in report['effect_cells']})==10
    assert report['captured_player_cell'] in report['effect_cells']
    assert all(c['passed'] for c in report['route_checks'])
    source_manifest=json.loads((Path(report['asset_dir'])/'manifest.json').read_text(encoding='utf-8'))
    slam_durations=source_manifest['clips']['shockwave_slam']['durations_ms']
    for capture in report['captures']:
        if 'titan_frame' not in capture:
            continue  # Inherited environment-only baseline captures.
        time=max(0,capture['time_ms']-report['slam_start_offset_ms'])
        cursor=0
        for frame,duration in enumerate(slam_durations):
            cursor+=duration
            if time<cursor or frame==len(slam_durations)-1:
                assert capture['titan_frame']==frame,'Titan and spike must use the same capture clock'
                break
    exports=[]
    sample_count=report['sample_count']
    step_ms=report['sample_interval_ms']
    for name,box,filename in [
        ('single-tile',(624,456,1008,760),'single-tile-red-spike-4x.webp'),
        ('ten-tiles',(352,96,1248,1120),'ten-tile-slam-map.webp'),
    ]:
        paths=sorted((render/name).glob('frame-*.png'))
        assert len(paths)==sample_count
        frames=[Image.open(p).convert('RGB').crop(box) for p in paths]
        target=output/filename
        frames[0].save(target,save_all=True,append_images=frames[1:],duration=[step_ms]*sample_count,loop=0,lossless=True,method=6)
        with Image.open(target) as animation:
            sample=0
            for i in range(animation.n_frames):
                animation.seek(i)
                animation.load()
                duration=animation.info['duration']
                assert duration%step_ms==0
                for _ in range(duration//step_ms):
                    assert animation.convert('RGB').tobytes()==frames[sample].tobytes()
                    sample+=1
            assert sample==sample_count
            encoded_frames=animation.n_frames
        exports.append({'file':filename,'samples':sample_count,'encoded_frames':encoded_frames,'duration_ms':step_ms*sample_count,
                        'crop':box,'source':'actual GPU pixels; no rescaling; identical frames folded with full duration',
                        'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    indices=[0,30,60,65,70,75,80,85,90,95,100,105,110,115,120,126]
    sheet=Image.new('RGB',(384*4,328*4),(32,29,27))
    draw=ImageDraw.Draw(sheet)
    for i,index in enumerate(indices):
        image=Image.open(render/f'single-tile/frame-{index:03}.png').convert('RGB').crop((624,456,1008,760))
        x=(i%4)*384
        y=(i//4)*328
        sheet.paste(image,(x,y+24))
        draw.text((x+8,y+6),f'{index*step_ms} ms',fill='white')
    sheet.save(output/'actual-4x-timeline.png')
    qa={'failures':0,'actual_gpu_captures':len(report['captures']),'previews':exports,'target_count':10,
        'target_cell_included':True,'source_report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest()}
    (output/'preview-qa.json').write_text(json.dumps(qa,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(qa))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    pack(args.render,args.output)
