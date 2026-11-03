"""Export exact-duration lossless previews from actual game captures."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import argparse,json,hashlib

def pack(source,output):
    output.mkdir(parents=True,exist_ok=True)
    report=json.loads((source/'review.json').read_text(encoding='utf-8'))
    assert not report['failures'] and report['captures']==301
    all_frames=[]
    exports=[]
    for mode,name in [('single','void-bolt.webp'),('aoe','shadow-eruption.webp')]:
        paths=sorted((source/mode).glob('*.png'))
        assert len(paths)==150
        frames=[Image.open(p).convert('RGB').crop((400,350,1200,1250)) for p in paths]
        frames[0].save(output/name,save_all=True,append_images=frames[1:],duration=[20]*150,loop=0,lossless=True,method=4)
        verify(output/name,frames)
        exports.append({'file':name,'samples':150,'duration_ms':3000,'sha256':hashlib.sha256((output/name).read_bytes()).hexdigest()})
        all_frames.append(frames)
    try:font=ImageFont.truetype('DejaVuSans.ttf',24)
    except OSError:font=ImageFont.load_default()
    pair=[]
    for i in range(150):
        frame=Image.new('RGB',(1600,944),(28,21,35));draw=ImageDraw.Draw(frame)
        draw.text((20,10),'Void Bolt | single target',font=font,fill=(219,179,255))
        draw.text((820,10),'Shadow Eruption | AoE',font=font,fill=(219,179,255))
        frame.paste(all_frames[0][i],(0,44));frame.paste(all_frames[1][i],(800,44))
        pair.append(frame)
    pair[0].save(output/'dark-magic-comparison.webp',save_all=True,append_images=pair[1:],duration=[20]*150,loop=0,lossless=True,method=4)
    verify(output/'dark-magic-comparison.webp',pair)
    Image.open(source/'casting-4x.png').save(output/'casting-4x.png')
    qa={'actual_game_captures':301,'source_frames_per_mode':150,'duration_ms':3000,'lossless_duration_and_pixel_roundtrip':'passed','exports':exports,'failures':0}
    (output/'preview-qa.json').write_text(json.dumps(qa,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(qa))

def verify(path,frames):
    with Image.open(path) as image:
        cursor=0
        for i in range(image.n_frames):
            image.seek(i);image.load();duration=image.info['duration']
            assert duration%20==0
            for _ in range(duration//20):
                assert image.convert('RGB').tobytes()==frames[cursor].tobytes()
                cursor+=1
        assert cursor==150

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();pack(args.source,args.output)
