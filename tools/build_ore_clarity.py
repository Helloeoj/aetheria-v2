"""Rebuild native128 ore PNGs from preserved inputs into a new output folder.

No generation, installation, runtime edits or source overwrites are performed.
The immutable original-library snapshot supplies the original96 palette paths.
"""
from __future__ import annotations

import argparse
from collections import deque
import colorsys
import hashlib
from io import BytesIO
import json
from pathlib import Path

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[1]
SIZE = 128


def _components(mask: np.ndarray):
    labels = np.zeros(mask.shape, np.int16)
    sizes = []
    for y, x in zip(*np.where(mask)):
        if labels[y, x]:
            continue
        number = len(sizes) + 1
        labels[y, x] = number
        queue = deque([(int(x), int(y))])
        count = 0
        while queue:
            u, v = queue.popleft()
            count += 1
            for xx, yy in ((u-1,v), (u+1,v), (u,v-1), (u,v+1)):
                if 0 <= xx < mask.shape[1] and 0 <= yy < mask.shape[0] and mask[yy, xx] and not labels[yy, xx]:
                    labels[yy, xx] = number
                    queue.append((xx, yy))
        sizes.append((count, number))
    return labels, sorted(sizes, reverse=True)


def _bbox(mask: np.ndarray):
    ys, xs = np.where(mask)
    if not len(xs):
        raise ValueError("A complete boulder silhouette is required")
    return int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)


def _split_rocks(mask: np.ndarray) -> np.ndarray:
    """Label the complete main/companion rocks using the accepted landmarks."""
    left, top, right, bottom = _bbox(mask)
    height, width = bottom-top, right-left
    yy, xx = np.mgrid[:mask.shape[0], :mask.shape[1]]
    big = ((xx-(left+width*.36))/(width*.40))**2 + ((yy-(top+height*.42))/(height*.49))**2
    small = ((xx-(left+width*.80))/(width*.23))**2 + ((yy-(top+height*.81))/(height*.23))**2
    return np.where(mask, np.where(small < big, 2, 1), 0).astype(np.uint8)


def _fill_rgb(rgb: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """Extend the nearest valid edge color for reconstructed boundary texels."""
    rgb, visited = rgb.copy(), valid.copy()
    ys, xs = np.where(valid)
    queue = deque(zip(xs.tolist(), ys.tolist()))
    while queue:
        x, y = queue.popleft()
        for u, v in ((x-1,y), (x+1,y), (x,y-1), (x,y+1)):
            if 0 <= u < valid.shape[1] and 0 <= v < valid.shape[0] and not visited[v, u]:
                rgb[v, u] = rgb[y, x]
                visited[v, u] = True
                queue.append((u, v))
    return rgb


def _register(source: Image.Image, original_alpha: Image.Image):
    """Register each complete generated rock to the finer original96 boundary."""
    target_mask = np.asarray(original_alpha.resize((SIZE,SIZE), Image.Resampling.BILINEAR)) >= 128
    old_labels = _split_rocks(np.asarray(original_alpha) >= 128)
    target_labels = np.asarray(Image.fromarray(old_labels).resize((SIZE,SIZE), Image.Resampling.NEAREST)).copy()
    target_labels[~target_mask] = 0
    # Bilinear boundary coverage includes texels outside nearest part labels.
    # Flood ownership into those texels instead of dropping their alpha.
    ys, xs = np.where(target_labels > 0)
    queue = deque(zip(xs.tolist(), ys.tolist()))
    while queue:
        u, v = queue.popleft()
        for x, y in ((u-1,v), (u+1,v), (u,v-1), (u,v+1)):
            if 0 <= x < SIZE and 0 <= y < SIZE and target_mask[y,x] and target_labels[y,x] == 0:
                target_labels[y,x] = target_labels[v,u]
                queue.append((x,y))
    source = source.convert("RGBA")
    small = source.resize((256,256), Image.Resampling.NEAREST)
    source_labels = _split_rocks(np.asarray(small)[:,:,3] >= 128)
    source_labels = np.asarray(Image.fromarray(source_labels).resize(source.size, Image.Resampling.NEAREST))
    source_pixels = np.asarray(source)
    result = np.zeros((SIZE,SIZE,4), np.uint8)
    records = []
    for part in (1,2):
        input_mask = (source_labels == part) & (source_pixels[:,:,3] >= 128)
        output_mask = (target_labels == part) & target_mask
        left, top, right, bottom = _bbox(input_mask)
        x, y, x2, y2 = _bbox(output_mask)
        pixels = source_pixels[top:bottom,left:right].copy()
        pixels[:,:,3] = np.where(input_mask[top:bottom,left:right],255,0)
        resized = np.asarray(Image.fromarray(pixels).resize((x2-x,y2-y), Image.Resampling.NEAREST))
        valid = resized[:,:,3] >= 128
        local = output_mask[y:y2,x:x2]
        missing = int((local & ~valid).sum())
        rgb = _fill_rgb(resized[:,:,:3], valid)
        result[y:y2,x:x2,:3][local] = rgb[local]
        result[:,:,3][output_mask] = 255
        records.append({"part":part, "source_bbox":[left,top,right,bottom], "target_bbox":[x,y,x2,y2],
                        "target_pixels":int(local.sum()), "reconstructed_edge_pixels":missing,
                        "edge_fraction":missing/max(1,int(local.sum()))})
    if not np.array_equal(result[:,:,3] == 255, target_mask):
        raise ValueError("Registration failed to retain the entire original silhouette")
    return Image.fromarray(result), records


def build(repo: Path, output: Path) -> dict:
    repo, output = Path(repo).resolve(), Path(output).resolve()
    ore_root = repo / "art_sources/ore-nodes"
    inputs = ore_root / "detail-v1"
    for protected in (ore_root, repo / "godot_client"):
        if output == protected or protected in output.parents:
            raise ValueError("Output must be separate from canonical source and runtime directories")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("Output folder must be new or empty; existing work is never overwritten")
    snapshot = repo / "tools/ore-integration/original-library.json"
    manifest = json.loads(snapshot.read_text(encoding="utf-8"))
    if manifest["native_canvas_size"] != [96,96] or len(manifest["entries"]) != 10:
        raise ValueError("Build requires the immutable original96 ten-ore snapshot")
    input_files = [snapshot]

    def load_rgba(path):
        input_files.append(path)
        with Image.open(path) as image:
            return image.convert("RGBA")

    original = ore_root / Path(manifest["entries"][0]["depleted"]["texture"]).name
    if hashlib.sha256(original.read_bytes()).hexdigest() != manifest["entries"][0]["depleted"]["source_sha256"]:
        raise ValueError("The original96 host source differs from the immutable snapshot")
    original_alpha = load_rgba(original).getchannel("A")
    host, host_registration = _register(load_rgba(inputs / "generated-depleted-host.png"), original_alpha)
    base = np.asarray(host).copy()
    palette_rgb = Image.fromarray(base[:,:,:3]).quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                                                       dither=Image.Dither.NONE).convert("RGB")
    base[:,:,:3] = np.asarray(palette_rgb)
    base[base[:,:,3] == 0,:3] = 0
    template, vein_registration = _register(load_rgba(inputs / "generated-mithril-template.png"), original_alpha)
    rgb = np.asarray(template)[:,:,:3]
    hsv = np.array([colorsys.rgb_to_hsv(*(v/255 for v in pixel)) for pixel in rgb.reshape(-1,3)]).reshape(SIZE,SIZE,3)
    vein = (base[:,:,3] == 255) & (hsv[:,:,0] > .62) & (hsv[:,:,0] < .86) & (hsv[:,:,1] > .14) & (hsv[:,:,2] > .07)
    labels, sizes = _components(vein)
    for size, number in sizes:
        if size < 2:
            vein[labels == number] = False
    if not 200 <= int(vein.sum()) <= 1200:
        raise ValueError(f"Unexpected mineral-mask area: {vein.sum()}")
    copper = np.asarray(load_rgba(ore_root / "copper-ore-full-south.png"))
    tin_provenance = ore_root / "tin-shared-shape-provenance.json"
    input_files.append(tin_provenance)
    tin = json.loads(tin_provenance.read_text(encoding="utf-8"))
    copper_colors = [tuple(bytes.fromhex(value[1:])) for value in tin["changes"][0]["colors"]]
    copper_colors.sort(key=lambda color:color[0]*.2126+color[1]*.7152+color[2]*.0722)
    levels = hsv[:,:,2]
    low, high = np.quantile(levels[vein],[.03,.97])
    if high <= low:
        raise ValueError("Mineral template must contain a varied finite shading ramp")
    shade = np.rint(np.clip((levels-low)/(high-low),0,1)*(len(copper_colors)-1)).astype(int)
    files = {}

    def encode(name, pixels, compress_level=6):
        stream = BytesIO()
        Image.fromarray(pixels).save(stream, format="PNG", compress_level=compress_level)
        files[name] = stream.getvalue()

    for entry in manifest["entries"]:
        source = ore_root / Path(entry["full"]["texture"]).name
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry["full"]["source_sha256"]:
            raise ValueError(f"{entry['id']}: original96 palette source differs from the immutable snapshot")
        old = np.asarray(load_rgba(source))
        ramp = []
        for color in copper_colors:
            selected = np.all(copper[:,:,:3] == color,axis=2) & (copper[:,:,3] > 0)
            values = np.unique(old[:,:,:3][selected],axis=0)
            if len(values) != 1:
                raise ValueError(f"{entry['id']}: original mineral color is not a shared palette variant")
            ramp.append(values[0])
        full = base.copy()
        full[:,:,:3][vein] = np.asarray(ramp,np.uint8)[shade[vein]]
        for state, pixels in (("full",full),("depleted",base)):
            encode(Path(entry[state]["texture"]).name,pixels,compress_level=9)
    encode("vein-mask.png",vein.astype(np.uint8)*255)
    encode("shared-alpha.png",base[:,:,3])
    encode("shared-host.png",base)
    report = {"native_size":[128,128], "world_canvas":[96,96], "world_pixels_per_source_pixel":.75,
              "image_anchor":[64,96], "world_anchor":[48,72], "alpha_pixels":int((base[:,:,3] > 0).sum()),
              "mineral_pixels":int(vein.sum()), "alpha_recipe":"original96 alpha PILBILINEAR resize128 then threshold>=128",
              "host_registration":host_registration, "vein_registration":vein_registration,
              "pillow_version":PILLOW_VERSION, "numpy_version":np.__version__,
              "inputs":{path.relative_to(repo).as_posix():hashlib.sha256(path.read_bytes()).hexdigest() for path in input_files},
              "files":{name:hashlib.sha256(data).hexdigest() for name,data in files.items()},
              "installation":"none; output only", "visual_approval":"separate; not conferred by rebuild"}
    output.mkdir(parents=True,exist_ok=True)
    for name, data in files.items():
        (output/name).write_bytes(data)
    (output/"build-report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo",type=Path,default=ROOT)
    parser.add_argument("--output",type=Path,required=True,help="New or empty output directory, outside canonical source/runtime")
    args = parser.parse_args()
    try:
        report = build(args.repo,args.output)
    except (OSError,ValueError,KeyError) as error:
        parser.exit(1,f"Ore clarity build failed: {error}\n")
    print(json.dumps(report,indent=2))


if __name__ == "__main__":
    main()
