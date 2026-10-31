"""Register restored raster contours to source before hard seam packaging.
Only coordinates are interpolated. Artwork sampling is always nearest, without
blending, sharpening, recoloring, generative fill, or changes to game geometry.
"""
from pathlib import Path
import sys,json,argparse
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--authoring',type=Path,default=Path(__file__).resolve().parents[1]/'art_sources/valtherian-mines/detail-v1')
parser.add_argument('--opencv-path',type=Path)
args=parser.parse_args()
if args.opencv_path: sys.path.insert(0,str(args.opencv_path))
import cv2

ROOT=args.authoring

def masks(a):
    a=a.astype(float)
    art=a.max(axis=2)>45
    floor=(a[:,:,0]>a[:,:,1]*1.17)&(a[:,:,1]>a[:,:,2]*1.22)&(a[:,:,1]>43)
    return art,floor

def signed(mask):
    return cv2.distanceTransform(mask.astype('uint8'),cv2.DIST_L2,5)-cv2.distanceTransform((~mask).astype('uint8'),cv2.DIST_L2,5)

def feature(a):
    art,floor=masks(a)
    value=128+np.clip(signed(art),-18,18)*3+np.clip(signed(floor),-18,18)*3
    return np.clip(value,0,255).astype('uint8')

def main():
    records=[]
    for j in json.loads((ROOT/'jobs.json').read_text()):
        ident=j['id']
        source=np.array(Image.open(ROOT/j['input']).convert('RGB'))
        raw=np.array(Image.open(ROOT/j['output']).convert('RGB'))
        small=np.array(Image.fromarray(raw).resize((260,260),Image.Resampling.NEAREST))
        target=feature(source)
        # A single affine registration preserves every generated straight edge,
        # facet and local proportion. Dense flow was trialled and rejected because
        # it deformed individual wall stones and floor marks.
        matrix=np.eye(2,3,dtype=np.float32)
        correlation,matrix=cv2.findTransformECC(target,feature(small),matrix,cv2.MOTION_AFFINE,
            (cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,500,1e-6),None,11)
        assert correlation>.92,(ident,correlation)
        assert .75<np.linalg.det(matrix[:,:2])<1.3,(ident,matrix)
        fx,fy=np.meshgrid(np.arange(raw.shape[1],dtype=np.float32),np.arange(raw.shape[0],dtype=np.float32))
        q=raw.shape[1]/260
        result=cv2.remap(raw,matrix[0,0]*fx+matrix[0,1]*fy+matrix[0,2]*q,
                         matrix[1,0]*fx+matrix[1,1]*fy+matrix[1,2]*q,
                         cv2.INTER_NEAREST,borderMode=cv2.BORDER_REPLICATE)
        Image.fromarray(result).save(ROOT/f'{ident}-registered.png')
        after=np.array(Image.fromarray(result).resize((260,260),Image.Resampling.NEAREST))
        m,_=masks(source);n,_=masks(small);r,_=masks(after)
        records.append({'id':ident,'original_art_pixels':int(m.sum()),
                        'before_content_xor':int(np.sum(m!=n)),
                        'after_content_xor':int(np.sum(m!=r)),
                        'affine_source_to_generated':matrix.tolist(),
                        'semantic_registration_correlation':correlation,
                        'method':'Single affine registration of semantic outer-art/ochre-floor distance fields; nearest artwork coordinate remap. No dense warp.'})
    (ROOT/'registration-report.json').write_text(json.dumps(records,indent=2))
    print(json.dumps(records))

if __name__=='__main__':main()
