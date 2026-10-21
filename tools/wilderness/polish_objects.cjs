'use strict';

// Reuse complete sprites from the original outskirts instead of stretching or
// cutting the flattened wilderness previews. Feet and collision data are kept.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const TREE_TEMPLATES = [
  'Outskirts_Trees_042', 'Outskirts_Trees_046', 'Outskirts_Trees_041',
  'Outskirts_Trees_023', 'Outskirts_Trees_049', 'Outskirts_Trees_052',
];
const ROCK_TEMPLATES = ['Outskirts_Rocks_015'];
// The old scene's rock anchor follows a manually placed collision. A reused
// sprite needs its own measured artwork anchor so its main boulder, rather than
// its small right pebble, sits over the new object's unchanged collision circle.
const TEMPLATE_ANCHORS = { Outskirts_Rocks_015: [27, 62] };
const PROTECTED_FIELDS = [
  'cell', 'foot', 'offset', 'collision_circles', 'collision_polygons',
  'authored_collision', 'walkable',
];

function largestAlphaComponent(data, width, height) {
  const seen = new Uint8Array(width * height);
  let largest = [];
  for (let first = 0; first < seen.length; first++) {
    if (seen[first] || data[first * 4 + 3] < 16) continue;
    const component = [first];
    seen[first] = 1;
    for (let q = 0; q < component.length; q++) {
      const p = component[q], px = p % width, py = Math.floor(p / width);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const x = px + dx, y = py + dy;
        if (x < 0 || x >= width || y < 0 || y >= height) continue;
        const n = y * width + x;
        if (!seen[n] && data[n * 4 + 3] >= 16) {
          seen[n] = 1;
          component.push(n);
        }
      }
    }
    if (component.length > largest.length) largest = component;
  }
  const keep = new Uint8Array(width * height);
  for (const p of largest) keep[p] = 1;
  for (let p = 0; p < keep.length; p++) if (!keep[p]) data[p * 4 + 3] = 0;
  return data;
}

function reviewedTreeTemplate(projectRoot, object) {
  if (!TREE_TEMPLATES.includes(object.name)) return null;
  const manifestPath = path.join(projectRoot, 'Assets/MapTiles/CleanTrees/manifest.json');
  if (!fs.existsSync(manifestPath)) return null;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  // Once the reviewed library is installed, every reused tree must come from
  // it. A partial library must not silently restore the old grass/shadow fringe.
  for (const name of TREE_TEMPLATES) {
    const entry = manifest.trees && manifest.trees[name];
    const expectedTexture = `res://Assets/MapTiles/CleanTrees/${name}.png`;
    if (!entry || entry.texture !== expectedTexture
        || !Array.isArray(entry.size) || entry.size.length !== 2
        || !entry.size.every(value => Number.isInteger(value) && value > 0)
        || !Array.isArray(entry.anchor) || entry.anchor.length !== 2
        || !entry.anchor.every(Number.isFinite)
        || !fs.existsSync(path.join(projectRoot, expectedTexture.slice(6)))) {
      throw new Error('Incomplete reviewed tree library: ' + name);
    }
  }
  const entry = manifest.trees[object.name];
  const anchor = object.sprite_offset.map(value => -value);
  if (entry.anchor.some((value, index) => value !== anchor[index])) {
    throw new Error('Reviewed tree anchor differs from its original donor: ' + object.name);
  }
  return entry;
}

async function readTemplate(projectRoot, object) {
  const reviewed = reviewedTreeTemplate(projectRoot, object);
  const texture = reviewed ? reviewed.texture : object.texture;
  const { data, info } = await sharp(path.join(projectRoot, texture.slice(6)))
    .ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (reviewed) {
    const original = await sharp(path.join(projectRoot, object.texture.slice(6))).metadata();
    if (info.width !== original.width || info.height !== original.height
        || reviewed.size[0] !== info.width || reviewed.size[1] !== info.height) {
      throw new Error('Reviewed tree canvas differs from its original donor: ' + object.name);
    }
    // Reviewed alpha is authoritative, including legitimate detached leaf tips.
    // Keep its original canvas so reuse preserves the existing anchor contract.
  } else {
    largestAlphaComponent(data, info.width, info.height);
  }
  let x0 = info.width, y0 = info.height, x1 = 0, y1 = 0;
  for (let p = 0; p < info.width * info.height; p++) if (data[p * 4 + 3]) {
    const x = p % info.width, y = Math.floor(p / info.width);
    x0 = Math.min(x0, x); y0 = Math.min(y0, y);
    x1 = Math.max(x1, x + 1); y1 = Math.max(y1, y + 1);
  }
  if (x0 >= x1 || y0 >= y1) throw new Error('Empty template: ' + object.name);
  if (reviewed) {
    x0 = 0; y0 = 0; x1 = info.width; y1 = info.height;
  }
  const width = x1 - x0, height = y1 - y0;
  const png = await sharp(data, { raw: { width: info.width, height: info.height, channels: 4 } })
    .extract({ left: x0, top: y0, width, height }).png().toBuffer();
  const anchor = TEMPLATE_ANCHORS[object.name] || object.sprite_offset.map(value => -value);
  return {
    name: object.name, texture, png, width, height,
    foot: [anchor[0] - x0, anchor[1] - y0],
  };
}

function nameHash(name) {
  let value = 2166136261;
  for (const c of name) value = Math.imul(value ^ c.charCodeAt(0), 16777619);
  return value >>> 0;
}

function selectTemplate(object, templates) {
  const desired = object.kind === 'Trees'
    ? Math.max(72, Math.min(350, -object.sprite_offset[1] + 8))
    : Math.max(30, Math.min(115, object.bbox[2]));
  const scored = [];
  for (const template of templates) {
    const dimension = object.kind === 'Trees' ? template.height : template.width;
    // One uniform scale for the complete sprite; no independent X/Y warp.
    const scale = Math.max(0.75, Math.min(1.25, Math.round(desired / dimension * 8) / 8));
    const error = Math.abs(Math.log(dimension * scale / desired));
    const scalePenalty = 0.09 * Math.abs(Math.log(scale));
    const variation = ((nameHash(object.name + template.name) % 1000) / 1000) * 0.055;
    scored.push({ template, scale, score: error + scalePenalty + variation });
  }
  scored.sort((a, b) => a.score - b.score);
  return scored[0];
}

async function cleanBuildingFringe(projectRoot, object, directory, resourceDirectory) {
  const { data, info } = await sharp(path.join(projectRoot, object.texture.slice(6)))
    .ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let removed = 0;
  // Green pixels above the lower facade are grass accidentally captured outside
  // the roof silhouette. Flower beds at the building base are intentionally kept.
  for (let y = 0; y < Math.floor(info.height * 0.66); y++) for (let x = 0; x < info.width; x++) {
    const p = (y * info.width + x) * 4;
    const r = data[p], g = data[p + 1], b = data[p + 2];
    if (data[p + 3] && g > r * 1.12 && g > b * 1.28 && g - r > 7) {
      data[p + 3] = 0;
      removed++;
    }
  }
  const filename = object.name + '_Clean.png';
  await sharp(data, { raw: { width: info.width, height: info.height, channels: 4 } })
    .png().toFile(path.join(directory, filename));
  object.texture = resourceDirectory + '/' + filename;
  return { name: object.name, removed_roof_fringe_pixels: removed };
}

async function polishObjects(manifest, options = {}) {
  const projectRoot = options.projectRoot || options.project || path.resolve(__dirname, '../../godot_client');
  const defaultResourceDirectory = 'res://Assets/MapTiles/Wilderness/PolishedObjects';
  const directory = options.outDir || path.join(projectRoot, (options.resourceDirectory || defaultResourceDirectory).slice(6));
  const relativeDirectory = path.relative(projectRoot, directory).replaceAll('\\', '/');
  if (relativeDirectory.startsWith('../') || path.isAbsolute(relativeDirectory)) {
    throw new Error('Polished sprites must be written inside the Godot project.');
  }
  const resourceDirectory = options.resourceDirectory || 'res://' + relativeDirectory;
  const oldManifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'Assets/MapTiles/map_manifest.json'), 'utf8'));
  const byName = new Map(oldManifest.objects.map(o => [o.name, o]));
  const treeTemplates = await Promise.all(TREE_TEMPLATES.map(name => readTemplate(projectRoot, byName.get(name))));
  const rockTemplates = await Promise.all(ROCK_TEMPLATES.map(name => readTemplate(projectRoot, byName.get(name))));
  const result = JSON.parse(JSON.stringify(manifest));
  const protectedBefore = JSON.stringify(result.objects.map(o => PROTECTED_FIELDS.map(k => o[k])));
  const rendered = new Map(), replacements = [], buildings = [];
  fs.mkdirSync(directory, { recursive: true });
  for (const object of result.objects) {
    // This utility may also receive a combined manifest. Original city/outskirts
    // objects remain untouched, including their authored collision resources.
    if (!object.name.startsWith('Wilderness')) continue;
    if (object.kind === 'Buildings' && options.cleanBuildings !== false) {
      buildings.push(await cleanBuildingFringe(projectRoot, object, directory, resourceDirectory));
      continue;
    }
    if (!['Trees', 'Rocks'].includes(object.kind)) continue;
    const { template, scale } = selectTemplate(object, object.kind === 'Trees' ? treeTemplates : rockTemplates);
    const key = template.name + '_s' + Math.round(scale * 1000);
    const filename = key + '.png';
    const width = Math.max(1, Math.round(template.width * scale));
    const height = Math.max(1, Math.round(template.height * scale));
    const anchor = template.foot.map(value => Math.round(value * scale));
    if (!rendered.has(key)) {
      await sharp(template.png).resize(width, height, { fit: 'fill', kernel: 'nearest' })
        .png().toFile(path.join(directory, filename));
      rendered.set(key, { template: template.name, scale, width, height, anchor });
    }
    const previousTexture = object.texture;
    object.texture = resourceDirectory + '/' + filename;
    object.sprite_offset = [-anchor[0], -anchor[1]];
    object.bbox = [object.foot[0] - anchor[0], object.foot[1] - anchor[1], width, height];
    object.complete_source_object = true;
    object.polished_from = template.texture;
    replacements.push({ name: object.name, previous_texture: previousTexture, template: template.name, scale, foot: object.foot });
  }
  const protectedAfter = JSON.stringify(result.objects.map(o => PROTECTED_FIELDS.map(k => o[k])));
  if (protectedBefore !== protectedAfter) throw new Error('Object polish modified protected placement or collision data.');
  const report = {
    tree_replacements: replacements.filter(o => o.name.includes('Trees') || o.name.includes('JoinTree')).length,
    rock_replacements: replacements.filter(o => o.name.includes('Rocks')).length,
    reusable_sprite_count: rendered.size,
    placements_and_collision_data_preserved: true,
    templates: [...rendered].map(([name, value]) => ({ name, ...value })),
    buildings, replacements,
  };
  if (options.reportPath) fs.writeFileSync(options.reportPath, JSON.stringify(report, null, 2) + '\n');
  return { manifest: result, report };
}

async function polishBorderTrees(options = {}) {
  const projectRoot = options.projectRoot || options.project || path.resolve(__dirname, '../../godot_client');
  const directory = options.outDir || path.join(projectRoot, 'Assets/MapTiles/Wilderness/PolishedObjects');
  const relativeDirectory = path.relative(projectRoot, directory).replaceAll('\\', '/');
  if (relativeDirectory.startsWith('../') || path.isAbsolute(relativeDirectory)) {
    throw new Error('Border tree sprites must be written inside the Godot project.');
  }
  const resourceDirectory = 'res://' + relativeDirectory;
  const oldManifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'Assets/MapTiles/map_manifest.json'), 'utf8'));
  const byName = new Map(oldManifest.objects.map(o => [o.name, o]));
  const replacements = [
    { name: 'Outskirts_Trees_017', donor: 'Outskirts_Trees_046', scale: 1 },
    { name: 'Outskirts_Trees_018', donor: 'Outskirts_Trees_046', scale: 1.125 },
    { name: 'Outskirts_Trees_019', donor: 'Outskirts_Trees_042', scale: 1.125 },
    { name: 'Outskirts_Trees_020', donor: 'Outskirts_Trees_046', scale: 1 },
  ];
  fs.mkdirSync(directory, { recursive: true });
  const overrides = [];
  for (const replacement of replacements) {
    const original = byName.get(replacement.name);
    const template = await readTemplate(projectRoot, byName.get(replacement.donor));
    const width = Math.round(template.width * replacement.scale);
    const height = Math.round(template.height * replacement.scale);
    const anchor = template.foot.map(value => Math.round(value * replacement.scale));
    const filename = 'Border_' + replacement.name + '_Complete.png';
    await sharp(template.png).resize(width, height, { fit: 'fill', kernel: 'nearest' })
      .png().toFile(path.join(directory, filename));
    overrides.push({
      name: original.name,
      texture: resourceDirectory + '/' + filename,
      sprite_offset: [-anchor[0], -anchor[1]],
      // Extra metadata is for inspection. The caller must only replace the
      // sprite resource and local sprite offset in a cloned PackedScene.
      bbox: [original.foot[0] - anchor[0], original.foot[1] - anchor[1], width, height],
      foot: [...original.foot],
      template: template.texture,
      uniform_scale: replacement.scale,
    });
  }
  return overrides;
}

module.exports = { polishObjects, polishBorderTrees, TREE_TEMPLATES, ROCK_TEMPLATES, PROTECTED_FIELDS };

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const value = flag => args[args.indexOf(flag) + 1];
    if (!args.includes('--manifest') || !args.includes('--output-manifest')) {
      throw new Error('Usage: node polish_objects.cjs --manifest input.json --output-manifest output.json [--project godot_client] [--report report.json]');
    }
    const options = {};
    if (args.includes('--project')) options.projectRoot = value('--project');
    if (args.includes('--report')) options.reportPath = value('--report');
    const input = JSON.parse(fs.readFileSync(value('--manifest'), 'utf8'));
    const result = await polishObjects(input, options);
    fs.writeFileSync(value('--output-manifest'), JSON.stringify(result.manifest, null, 2) + '\n');
    console.log(JSON.stringify({ ...result.report, templates: result.report.templates.length, replacements: result.report.replacements.length }, null, 2));
  })().catch(error => { console.error(error); process.exitCode = 1; });
}
