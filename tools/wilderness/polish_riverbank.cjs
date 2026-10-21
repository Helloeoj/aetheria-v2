'use strict';

// Fine shoreline details, using native original-map stones and water colors.
// The shoreline positions and collision classification remain authoritative.
const path = require('node:path');
const sharp = require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

function noise(x, y, seed = 971) {
  let n = Math.imul(x + 1013904223, 1664525) ^ Math.imul(y + seed, 1013904223);
  n = Math.imul(n ^ (n >>> 16), 2246822519);
  n = Math.imul(n ^ (n >>> 13), 3266489917);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

async function read(project, relative) {
  return sharp(path.join(project, relative)).ensureAlpha().raw().toBuffer({resolveWithObject: true});
}

function sampledPalette(water) {
  const colors = new Map();
  for (let p = 0; p < water.data.length; p += 28) {
    const r = water.data[p], g = water.data[p + 1], b = water.data[p + 2], a = water.data[p + 3];
    if (a < 250 || b < g * 1.02 || g < r * 1.15 || r < 25 || r > 155 || g > 190 || b > 225) continue;
    const key = `${r >> 3},${g >> 3},${b >> 3}`;
    if (!colors.has(key)) colors.set(key, {color: [r, g, b], count: 0});
    colors.get(key).count++;
  }
  const candidates = [...colors.values()].filter(item => item.count >= 3);
  if (!candidates.length) throw new Error('Cannot sample original water palette for riverbank.');
  const closest = target => candidates.reduce((best, item) => {
    const distance = item.color.reduce((sum, channel, i) => sum + (channel - target[i]) ** 2, 0);
    return !best || distance < best.distance ? {distance, color: item.color} : best;
  }, null).color;
  return {
    edge: closest([49, 100, 128]),
    shallow: closest([61, 116, 148]),
    foam: closest([81, 139, 166]),
  };
}

function put(rgba, width, height, x, y, rgb) {
  if (x < 0 || y < 0 || x >= width || y >= height) return false;
  const p = (y * width + x) * 4;
  rgba[p] = rgb[0];
  rgba[p + 1] = rgb[1];
  rgba[p + 2] = rgb[2];
  rgba[p + 3] = 255;
  return true;
}

function stamp(rgba, width, height, terrainMask, sprite, x, y, underwater) {
  if (x < 0 || y < 0 || x + sprite.info.width > width || y + sprite.info.height > height) return 0;
  let pixels = 0;
  let waterPixels = 0;
  for (let sy = 0; sy < sprite.info.height; sy++) {
    for (let sx = 0; sx < sprite.info.width; sx++) {
      const p = (sy * sprite.info.width + sx) * 4;
      if (!sprite.data[p + 3]) continue;
      pixels++;
      if (terrainMask[(y + sy) * width + x + sx] === 2) waterPixels++;
    }
  }
  if (!pixels || (underwater && waterPixels !== pixels)) return 0;
  if (!underwater && waterPixels > pixels * 0.5) return 0;
  for (let sy = 0; sy < sprite.info.height; sy++) {
    for (let sx = 0; sx < sprite.info.width; sx++) {
      const p = (sy * sprite.info.width + sx) * 4;
      if (!sprite.data[p + 3]) continue;
      const target = ((y + sy) * width + x + sx) * 4;
      sprite.data.copy(rgba, target, p, p + 4);
    }
  }
  return pixels;
}

/**
 * shore[y] is the coast's X coordinate in the supplied image canvas.
 * terrainMask contains 0 grass, 1 road/bank, 2 blocked water.
 * Returns a complete GroundDetails RGBA buffer, including the optional input.
 * No terrain masks, collision geometry, source PNGs or large boulders are added.
 */
async function paintRiverbank({project, width, height, shore, terrainMask, rgba: previous}) {
  if (!project || !Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new Error('paintRiverbank requires project and positive integer canvas dimensions.');
  }
  if (!shore || shore.length !== height || !terrainMask || terrainMask.length !== width * height) {
    throw new Error('paintRiverbank requires shore[height] and terrainMask[width*height].');
  }
  if (previous && previous.length !== width * height * 4) throw new Error('paintRiverbank rgba has incorrect length.');
  const rgba = previous ? Buffer.from(previous) : Buffer.alloc(width * height * 4);
  const water = await read(project, 'Assets/MapTiles/Water.png');
  const palette = sampledPalette(water);
  let edgePixels = 0, foamPixels = 0;
  // Broken shallow-water accents follow each row at native one-pixel steps.
  // Gaps and irregular depth keep the detail from becoming a bright outline.
  for (let y = 2; y < height - 2; y++) {
    const coast = Math.ceil(shore[y]);
    if (!Number.isFinite(coast) || coast < 1 || coast >= width - 2) continue;
    const segment = Math.floor(y / 13);
    const phase = (y + Math.floor(noise(segment, 3) * 11)) % 13;
    for (let dx = 0; dx < 3; dx++) {
      const x = coast + dx;
      if (x >= width || terrainMask[y * width + x] !== 2) continue;
      if (noise(x >> 1, y >> 1, 1097) < (dx === 0 ? 0.65 : 0.22)) {
        if (put(rgba, width, height, x, y, dx === 0 ? palette.edge : palette.shallow)) edgePixels++;
      }
    }
    if (phase < 7 && noise(segment, 23) > 0.30) {
      const offset = 2 + Math.floor(noise(segment, 29) * 5);
      const widthHere = phase === 0 || phase === 6 ? 1 : 2;
      for (let dx = 0; dx < widthHere; dx++) {
        const x = coast + offset + dx;
        if (x >= width || terrainMask[y * width + x] !== 2) continue;
        if (noise(x, y, 1119) > 0.22 && put(rgba, width, height, x, y, palette.foam)) foamPixels++;
      }
    }
  }
  const stones = [];
  for (const id of [3, 5, 6]) {
    const file = `Assets/MapTiles/Objects/Outskirts_Rocks_${String(id).padStart(3, '0')}.png`;
    stones.push({...await read(project, file), source: `res://${file}`});
  }
  const placements = [];
  let stonePixels = 0;
  // About one pebble per 60-90 pixels of bank, with occasional bare stretches.
  for (let row = 20; row < height - 24; row += 31) {
    if (noise(row, 83) < 0.50) continue;
    const sprite = stones[Math.floor(noise(row, 89) * stones.length)];
    const y = row + Math.floor(noise(row, 97) * 13);
    const underwater = noise(row, 101) < 0.82;
    const x = Math.ceil(shore[y]) + (underwater ? 3 + Math.floor(noise(row, 103) * 7) : -8 - sprite.info.width);
    const copied = stamp(rgba, width, height, terrainMask, sprite, x, y, underwater);
    if (!copied) continue;
    stonePixels += copied;
    placements.push({source: sprite.source, position: [x, y], size: [sprite.info.width, sprite.info.height], underwater});
  }
  return {rgba, report: {
    version: 1,
    method: 'Native original-map tiny stones and sparse broken water accents in the original water palette',
    palette,
    edge_pixels: edgePixels,
    foam_pixels: foamPixels,
    stone_pixels: stonePixels,
    stone_count: placements.length,
    underwater_stone_count: placements.filter(item => item.underwater).length,
    shoreline_and_terrain_mask_unchanged: true,
    source_art_scale: 1,
    added_collision_objects: 0,
    placements,
  }};
}

module.exports = {paintRiverbank};
