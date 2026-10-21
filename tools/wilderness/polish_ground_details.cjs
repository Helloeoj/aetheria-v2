'use strict';

// Reuse intact, measured original-map growth sprites at their native pixel size.
// This module never reads the damaged wilderness GroundDetails atlas.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const GRASS_IDS = [30, 33, 34, 37, 45, 53];
const FLOWER_IDS = [21, 26, 27, 40, 50, 51];
const REFERENCE_AREA = 3072 * 3072;

function randomGenerator(seed) {
  let state = (seed >>> 0) || 0x6d2b79f5;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
}

function pair(value, fallback = [0, 0]) {
  if (Array.isArray(value)) return value;
  if (value && Number.isFinite(value.x) && Number.isFinite(value.y)) return [value.x, value.y];
  return fallback;
}

async function readSprites(project) {
  const sprites = [];
  for (const [kind, ids] of [['Grass', GRASS_IDS], ['Flowers', FLOWER_IDS]]) {
    for (const id of ids) {
      const name = `Outskirts_Trees_${String(id).padStart(3, '0')}`;
      const relative = `Assets/MapTiles/Objects/${name}.png`;
      const texture = path.join(project, relative);
      const decoded = await sharp(texture).ensureAlpha().raw().toBuffer({resolveWithObject: true});
      sprites.push({name, kind, texture: `res://${relative}`, data: decoded.data, width: decoded.info.width, height: decoded.info.height});
    }
  }
  return sprites;
}

function addDisc(mask, width, height, x, y, radius) {
  const x0 = Math.max(0, Math.floor(x - radius));
  const x1 = Math.min(width - 1, Math.ceil(x + radius));
  const y0 = Math.max(0, Math.floor(y - radius));
  const y1 = Math.min(height - 1, Math.ceil(y + radius));
  for (let py = y0; py <= y1; py++) {
    for (let px = x0; px <= x1; px++) {
      if ((px - x) ** 2 + (py - y) ** 2 <= radius ** 2) mask[py * width + px] = 1;
    }
  }
}

function addRectangle(mask, width, height, x, y, w, h, margin) {
  const x0 = Math.max(0, Math.floor(x - margin));
  const y0 = Math.max(0, Math.floor(y - margin));
  const x1 = Math.min(width, Math.ceil(x + w + margin));
  const y1 = Math.min(height, Math.ceil(y + h + margin));
  if (x0 >= x1 || y0 >= y1) return;
  for (let py = y0; py < y1; py++) mask.fill(1, py * width + x0, py * width + x1);
}

function forbiddenMask(width, height, origin, terrainMask, objects) {
  const blocked = new Uint8Array(width * height);
  for (let i = 0; i < blocked.length; i++) blocked[i] = terrainMask[i] === 0 ? 0 : 1;
  for (const object of objects) {
    const kind = String(object.kind || '').toLowerCase();
    const box = object.bbox;
    if ((kind.includes('building') || kind.includes('wheat')) && Array.isArray(box) && box.length >= 4) {
      addRectangle(blocked, width, height, box[0] - origin[0], box[1] - origin[1], box[2], box[3], kind.includes('building') ? 26 : 16);
      continue;
    }
    if (!object.foot) continue;
    const foot = pair(object.foot);
    const x = foot[0] - origin[0], y = foot[1] - origin[1];
    const circles = [...(object.collision_circles || [])];
    if (object.collision_circle) circles.push(object.collision_circle);
    if (circles.length) {
      for (const circle of circles) {
        const offset = pair(circle.position);
        addDisc(blocked, width, height, x + offset[0], y + offset[1], Number(circle.radius || 0) + 22);
      }
    } else if (!kind.includes('ground')) {
      addDisc(blocked, width, height, x, y, kind.includes('tree') ? 42 : 35);
    }
  }
  return blocked;
}

function summedArea(mask, width, height) {
  const stride = width + 1;
  const sum = new Uint32Array(stride * (height + 1));
  for (let y = 0; y < height; y++) {
    let row = 0;
    for (let x = 0; x < width; x++) {
      row += mask[y * width + x];
      sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + row;
    }
  }
  return {sum, stride};
}

function rectangleCount(area, x0, y0, x1, y1) {
  const {sum, stride} = area;
  return sum[y1 * stride + x1] - sum[y0 * stride + x1] - sum[y1 * stride + x0] + sum[y0 * stride + x0];
}

function copySprite(destination, width, sprite, x, y) {
  let opaquePixels = 0;
  for (let sy = 0; sy < sprite.height; sy++) {
    for (let sx = 0; sx < sprite.width; sx++) {
      const from = (sy * sprite.width + sx) * 4;
      if (!sprite.data[from + 3]) continue;
      const to = ((y + sy) * width + x + sx) * 4;
      destination[to] = sprite.data[from];
      destination[to + 1] = sprite.data[from + 1];
      destination[to + 2] = sprite.data[from + 2];
      destination[to + 3] = sprite.data[from + 3];
      opaquePixels++;
    }
  }
  return opaquePixels;
}

/**
 * @param {object} options
 * @param {string} options.project Absolute godot_client directory.
 * @param {number} options.width Terrain image width in pixels.
 * @param {number} options.height Terrain image height in pixels.
 * @param {[number,number]} options.origin World position of its top-left corner.
 * @param {Uint8Array} options.terrainMask 0 grass, 1 road, 2 water, row-major.
 * @param {Array<object>} options.objects Manifest entries in world coordinates.
 * @param {string} [options.output] Optional destination PNG; no source assets are written.
 * @returns {Promise<{rgba:Buffer,data:Buffer,report:object}>}
 */
async function paintGroundDetails({project, width, height, origin = [0, 0], terrainMask, objects = [], output, seed = 0x5eeda37, grassCount, flowerCount}) {
  if (!project || !Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new Error('paintGroundDetails requires project and positive integer width/height.');
  }
  if (!terrainMask || terrainMask.length !== width * height) {
    throw new Error('paintGroundDetails terrainMask must contain one class per image pixel.');
  }
  origin = pair(origin);
  const sprites = await readSprites(project);
  const area = summedArea(forbiddenMask(width, height, origin, terrainMask, objects), width, height);
  const rgba = Buffer.alloc(width * height * 4);
  const random = randomGenerator(seed);
  const requested = {
    Grass: grassCount ?? Math.round(160 * width * height / REFERENCE_AREA),
    Flowers: flowerCount ?? Math.round(40 * width * height / REFERENCE_AREA),
  };
  const placements = [];
  let opaquePixels = 0;
  let attempted = 0;
  for (const kind of ['Grass', 'Flowers']) {
    const candidates = sprites.filter(sprite => sprite.kind === kind);
    const target = Math.max(0, Math.floor(requested[kind]));
    let placed = 0;
    for (let attempt = 0; attempt < Math.max(1000, target * 180) && placed < target; attempt++) {
      attempted++;
      const sprite = candidates[Math.floor(random() * candidates.length)];
      const clearance = 10;
      const border = 18;
      if (width < sprite.width + border * 2 || height < sprite.height + border * 2) continue;
      const x = border + Math.floor(random() * (width - sprite.width - border * 2));
      const y = border + Math.floor(random() * (height - sprite.height - border * 2));
      if (rectangleCount(area, x - clearance, y - clearance, x + sprite.width + clearance, y + sprite.height + clearance)) continue;
      const center = [x + sprite.width * 0.5, y + sprite.height * 0.5];
      if (placements.some(other => (center[0] - other.center[0]) ** 2 + (center[1] - other.center[1]) ** 2 < 105 ** 2)) continue;
      opaquePixels += copySprite(rgba, width, sprite, x, y);
      placements.push({kind, source: sprite.texture, position: [x + origin[0], y + origin[1]], image_position: [x, y], size: [sprite.width, sprite.height], center});
      placed++;
    }
  }
  const report = {
    version: 1,
    method: 'Whole original-map low-growth sprites, native pixel size, deterministic sparse grass-only placement',
    seed,
    size: [width, height],
    origin,
    requested,
    placed: {Grass: placements.filter(p => p.kind === 'Grass').length, Flowers: placements.filter(p => p.kind === 'Flowers').length},
    attempts: attempted,
    opaque_pixels: opaquePixels,
    coverage: opaquePixels / (width * height),
    collision: false,
    y_sort: false,
    source_images_unchanged: true,
    old_wilderness_ground_details_used: false,
    placements: placements.map(({center, ...placement}) => placement),
  };
  if (output) {
    fs.mkdirSync(path.dirname(output), {recursive: true});
    await sharp(rgba, {raw: {width, height, channels: 4}}).png({compressionLevel: 6}).toFile(output);
  }
  return {rgba, data: rgba, report};
}

module.exports = {paintGroundDetails};
