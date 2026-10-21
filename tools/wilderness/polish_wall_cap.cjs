const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

// The existing north tower is cut by the original source image's upper edge.
// Reuse its matching middle tower at native scale, retaining the existing lower
// crown and all old wall/collision resources. This asset adds only the missing top.
async function buildWallCap({ project, outDir, clipBelowZero = true }) {
  if (!project) throw new Error('buildWallCap requires the Godot project directory.');
  const projectRoot = fs.existsSync(path.join(project, 'project.godot'))
    ? path.resolve(project)
    : path.resolve(project, 'godot_client');
  const source = path.join(projectRoot, 'Assets/MapTiles/Objects/Outskirts_Walls_000.png');
  const directory = path.resolve(outDir || path.join(projectRoot, 'Assets/MapTiles/Wilderness/Objects'));
  fs.mkdirSync(directory, { recursive: true });

  const crop = { left: 122, top: 282, width: 118, height: 92 };
  const target = { x: 122, y: -44 };
  const height = clipBelowZero ? -target.y : crop.height;
  const { data, info } = await sharp(source)
    .extract({ ...crop, height })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  // The source wall continues north behind this tower. Remove that attached
  // wall using the hand-traced *outer* backs of the native crenellations.
  // All retained RGBA pixels remain exact source pixels; no scaling or painting.
  const topContour = [
    [122, 315], [128, 310], [135, 306], [142, 297],
    [151, 288], [157, 291], [165, 296], [168, 296],
    [169, 283], [191, 283], [192, 296], [197, 295],
    [205, 287], [211, 290], [224, 299], [231, 306],
    [237, 312], [240, 317],
  ];
  for (let x = 0; x < info.width; x++) {
    const sourceX = x + crop.left;
    let top = topContour[topContour.length - 1][1];
    for (let i = 0; i < topContour.length - 1; i++) {
      const a = topContour[i], b = topContour[i + 1];
      if (sourceX >= a[0] && sourceX <= b[0]) {
        top = a[1] + (b[1] - a[1]) * (sourceX - a[0]) / (b[0] - a[0]);
        break;
      }
    }
    for (let y = 0; y < height; y++) {
      if (y + crop.top < Math.ceil(top)) data[(y * info.width + x) * 4 + 3] = 0;
    }
  }

  const output = path.join(directory, 'Wilderness_NorthWallCap.png');
  await sharp(data, { raw: { width: info.width, height, channels: 4 } }).png().toFile(output);
  const relativeTexture = path.relative(projectRoot, output).replaceAll('\\', '/');
  const texture = relativeTexture.startsWith('../') ? output.replaceAll('\\', '/') : 'res://' + relativeTexture;
  const foot = [181, -1];
  const cell = foot.map(n => Math.floor(n / 32));
  return {
    name: 'Wilderness_NorthWallCap',
    kind: 'Walls',
    section: '01',
    source_name: 'Native north-tower crown extension',
    texture,
    foot,
    cell,
    offset: foot.map((n, i) => n - (cell[i] * 32 + 16)),
    sprite_offset: [target.x - foot[0], target.y - foot[1]],
    bbox: [target.x, target.y, crop.width, height],
    collision_polygons: [[[-53, -27], [52, -27], [52, 1], [-53, 1]]],
    native_source: {
      texture: 'res://Assets/MapTiles/Objects/Outskirts_Walls_000.png',
      crop: [crop.left, crop.top, crop.width, height],
      translated_by: [0, -326],
      scale: 1,
      original_pixels_below_zero_untouched: clipBelowZero,
      method: 'Native crown crop with only the attached wall above its crenellations alpha-masked.',
    },
  };
}

module.exports = { buildWallCap };
