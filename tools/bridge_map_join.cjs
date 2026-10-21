'use strict';

// The old scene ends at y=1024. These helpers change only rows below it.
const JOIN_ROWS = 128;
const REFERENCE_WIDTH = 1536;

function checkRgba(buffer, width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 2 || height < 1 ||
      !buffer || buffer.length !== width * height * 4) {
    throw new Error('Map join requires a full-canvas RGBA buffer and valid dimensions');
  }
}

/**
 * Warp a full-canvas harbor layer in place, returning the same buffer.
 * Call on every harbor layer after placing it at startY and before extracting
 * connected objects, filling terrain, or deriving collision geometry.
 *
 * At the join, source shore x=1406 reaches x=1472. The path center x=1176,
 * left edge, and right edge stay fixed. Nearest sampling retains source colors
 * and transparent edges; all offsets reach zero after 128 new rows.
 */
function warpHarborLayer(buffer, width, height, startY = 1024) {
  checkRgba(buffer, width, height);
  if (!Number.isInteger(startY) || startY < 0 || startY > height) {
    throw new Error('Map join startY must be within the canvas');
  }
  const scale = (width - 1) / (REFERENCE_WIDTH - 1);
  const pathX = 1176 * scale;
  const sourceShore = 1406 * scale;
  const shift = 66 * scale;
  const right = width - 1;
  const row = Buffer.alloc(width * 4);
  const lastY = Math.min(height, startY + JOIN_ROWS);
  for (let y = startY; y < lastY; y++) {
    const t = (y - startY) / JOIN_ROWS;
    const smooth = t * t * (3 - 2 * t);
    const destinationShore = sourceShore + shift * (1 - smooth);
    const rowOffset = y * width * 4;
    buffer.copy(row, 0, rowOffset, rowOffset + row.length);
    for (let x = 0; x < width; x++) {
      let sx = x;
      if (x > pathX && x <= destinationShore) {
        sx = pathX + (x - pathX) * (sourceShore - pathX) / (destinationShore - pathX);
      } else if (x > destinationShore) {
        sx = sourceShore + (x - destinationShore) * (right - sourceShore) / (right - destinationShore);
      }
      sx = Math.max(0, Math.min(width - 1, Math.round(sx)));
      row.copy(buffer, rowOffset + x * 4, sx * 4, sx * 4 + 4);
    }
  }
  return buffer;
}

function patchNoise(x, y) {
  // Small irregular patches preserve crisp texture without a blurred band.
  // Offset alternating rows so the noise does not form a regular square grid.
  const py = Math.floor(y / 3);
  const px = Math.floor((x + (py & 1)) / 3);
  let n = Math.imul(px + 1, 0x45d9f3b) ^ Math.imul(py + 17, 0x119de1f3);
  n = Math.imul(n ^ (n >>> 16), 0x45d9f3b);
  n ^= n >>> 16;
  return (n >>> 0) / 4294967296;
}

/**
 * Replace the terrain color blend after backing fill and classification.
 * terrain is the existing array [grass, paths, water, groundDetails] of full
 * RGBA buffers; cls is its per-pixel surface class (0, 1, or 2).
 *
 * In the new 128-row band only, select complete pixels from mirrored old
 * terrain with decreasing probability. Copy only opaque, same-class pixels.
 * The class map, alpha, ground details, and extracted object sprites remain
 * unchanged, so shore collision geometry continues to match the warped layers.
 * Returns the same terrain array.
 */
function blendTerrainJoin(terrain, cls, width, height, oldHeight = 1024) {
  if (!Array.isArray(terrain) || terrain.length < 3 || !cls || cls.length !== width * height) {
    throw new Error('Map join requires three terrain surfaces and a surface class map');
  }
  for (let i = 0; i < 3; i++) checkRgba(terrain[i], width, height);
  if (!Number.isInteger(oldHeight) || oldHeight < 1 || oldHeight > height) {
    throw new Error('Map join oldHeight must be within the canvas');
  }
  const lastY = Math.min(height, oldHeight + JOIN_ROWS);
  for (let y = oldHeight; y < lastY; y++) {
    const dy = y - oldHeight;
    const t = dy / JOIN_ROWS;
    const oldProbability = 1 - t * t * (3 - 2 * t);
    const sourceY = Math.max(0, oldHeight - 1 - dy);
    for (let x = 0; x < width; x++) {
      const p = y * width + x;
      const q = sourceY * width + x;
      const surface = cls[p];
      if (surface > 2 || surface !== cls[q] || patchNoise(x, dy) >= oldProbability) continue;
      const layer = terrain[surface];
      const target = p * 4;
      const source = q * 4;
      if (layer[target + 3] !== 255 || layer[source + 3] !== 255) continue;
      layer[target + 0] = layer[source + 0];
      layer[target + 1] = layer[source + 1];
      layer[target + 2] = layer[source + 2];
    }
  }
  return terrain;
}

module.exports = { warpHarborLayer, blendTerrainJoin };
