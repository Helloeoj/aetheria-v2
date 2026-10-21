'use strict';

// Align approved source pixels at shared edges without painting or recoloring.
// Image input: {data: Buffer|Uint8Array, width, height, channels: 4}.
// Output map[destinationPixel] is its nearest-neighbor source pixel index.
const EDGE_DEPTH = 192;
const STRIP_DEPTH = 12;

function imageData(image) {
  const data = image.data || image.rgba;
  const width = Number(image.width), height = Number(image.height);
  if (!data || !width || !height || data.length < width * height * 4) {
    throw new Error('An RGBA image with data, width, and height is required.');
  }
  return {data, width, height};
}

function roadPixel(r, g, b) {
  return r > 105 && g > 55 && r - g > 18 && g - b > 14 && b < 155;
}

function waterPixel(r, g, b) {
  return b > 65 && b > r * 1.12 && g > r * 1.10 && b > g * 1.025;
}

function edgeProfile(image, side) {
  const {data, width, height} = imageData(image);
  const horizontal = side === 'top' || side === 'bottom';
  const length = horizontal ? width : height;
  const depth = Math.min(STRIP_DEPTH, horizontal ? height : width);
  const road = new Float32Array(length), water = new Float32Array(length);
  for (let t = 0; t < length; t++) {
    for (let d = 0; d < depth; d++) {
      const x = horizontal ? t : side === 'left' ? d : width - 1 - d;
      const y = horizontal ? side === 'top' ? d : height - 1 - d : t;
      const i = (y * width + x) * 4;
      if (data[i + 3] < 128) continue;
      if (roadPixel(data[i], data[i + 1], data[i + 2])) road[t]++;
      if (waterPixel(data[i], data[i + 1], data[i + 2])) water[t]++;
    }
    road[t] /= depth;
    water[t] /= depth;
  }
  return {length, road, water};
}

function runs(profile, threshold, gapSize = 10) {
  const flags = Uint8Array.from(profile, value => value >= threshold ? 1 : 0);
  // Small stones and foam should not split one road or water run.
  for (let i = 0; i < flags.length;) {
    if (flags[i]) { i++; continue; }
    const start = i;
    while (i < flags.length && !flags[i]) i++;
    if (start > 0 && i < flags.length && i - start <= gapSize) flags.fill(1, start, i);
  }
  const output = [];
  for (let i = 0; i < flags.length;) {
    if (!flags[i]) { i++; continue; }
    const start = i;
    while (i < flags.length && flags[i]) i++;
    if (i - start >= 8) output.push({start, end: i, center: (start + i) / 2, width: i - start});
  }
  return output;
}

function measureEdge(image, side) {
  const profile = edgeProfile(image, side);
  const roadRuns = runs(profile.road, 0.28, 13);
  // The broad edge-crossing road wins over isolated brown trunks and twigs.
  roadRuns.sort((a, b) => b.width - a.width);
  const waterRuns = runs(profile.water, 0.25, 18);
  waterRuns.sort((a, b) => b.width - a.width);
  return {
    road: roadRuns[0] || null,
    water: waterRuns.find(run => run.end >= profile.length - 4) || waterRuns[0] || null,
    length: profile.length,
  };
}

function measureSectionEdges(image) {
  return Object.fromEntries(['top', 'bottom', 'left', 'right'].map(side => [side, measureEdge(image, side)]));
}

function meanRoad(a, b) {
  if (!a || !b) throw new Error('A shared road was not detected on both edges.');
  return {start: (a.start + b.start) / 2, end: (a.end + b.end) / 2};
}

function controls(edge, target, length) {
  const pairs = [[0, 0], [length - 1, length - 1]];
  if (target.road) {
    if (!edge.road) throw new Error('A road alignment target has no source road.');
    pairs.push([target.road.start, edge.road.start], [target.road.end, edge.road.end]);
  }
  if (target.shore !== undefined) {
    if (!edge.water) throw new Error('A shoreline alignment target has no source water.');
    pairs.push([target.shore, edge.water.start]);
  }
  pairs.sort((a, b) => a[0] - b[0]);
  for (let i = 1; i < pairs.length; i++) {
    if (pairs[i][0] <= pairs[i - 1][0] || pairs[i][1] <= pairs[i - 1][1]) {
      throw new Error('Edge alignment controls are not monotonic.');
    }
  }
  return pairs;
}

function interpolate(value, pairs) {
  for (let i = 1; i < pairs.length; i++) {
    if (value <= pairs[i][0]) {
      const a = pairs[i - 1], b = pairs[i];
      return a[1] + (value - a[0]) * (b[1] - a[1]) / (b[0] - a[0]);
    }
  }
  return value;
}

function edgeWeight(distance) {
  if (distance >= EDGE_DEPTH) return 0;
  const t = 1 - Math.max(0, distance) / EDGE_DEPTH;
  return t * t * (3 - 2 * t);
}

function buildWarp(image, measurements, targets) {
  const {width, height} = imageData(image);
  const sideControls = Object.fromEntries(Object.entries(targets).map(([side, target]) => [
    side, controls(measurements[side], target, side === 'left' || side === 'right' ? height : width),
  ]));
  function sourcePoint(x, y) {
    let sx = x, sy = y;
    if (sideControls.top) sx += (interpolate(x, sideControls.top) - x) * edgeWeight(y);
    if (sideControls.bottom) sx += (interpolate(x, sideControls.bottom) - x) * edgeWeight(height - 1 - y);
    if (sideControls.left) sy += (interpolate(y, sideControls.left) - y) * edgeWeight(x);
    if (sideControls.right) sy += (interpolate(y, sideControls.right) - y) * edgeWeight(width - 1 - x);
    return [sx, sy];
  }
  const map = new Int32Array(width * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const [sx, sy] = sourcePoint(x, y);
      const ix = Math.max(0, Math.min(width - 1, Math.round(sx)));
      const iy = Math.max(0, Math.min(height - 1, Math.round(sy)));
      map[y * width + x] = iy * width + ix;
    }
  }
  // Invert the monotonic local map for object feet and collider control points.
  function forwardPoint(x, y) {
    let dx = x, dy = y;
    for (let iteration = 0; iteration < 12; iteration++) {
      let lo = 0, hi = width - 1;
      for (let step = 0; step < 24; step++) {
        const mid = (lo + hi) * 0.5;
        if (sourcePoint(mid, dy)[0] < x) lo = mid; else hi = mid;
      }
      dx = (lo + hi) * 0.5;
      lo = 0; hi = height - 1;
      for (let step = 0; step < 24; step++) {
        const mid = (lo + hi) * 0.5;
        if (sourcePoint(dx, mid)[1] < y) lo = mid; else hi = mid;
      }
      dy = (lo + hi) * 0.5;
    }
    return [dx, dy];
  }
  return {map, forwardPoint, sourcePoint, width, height, measurements, targets, edgeDepth: EDGE_DEPTH};
}

function planSectionWarps(sectionMap, oldMap) {
  const images = Object.fromEntries(Object.entries(sectionMap).map(([id, image]) => [String(id).slice(0, 2), image]));
  for (const id of ['01', '02', '03', '04']) {
    if (!images[id]) throw new Error('Missing wilderness section ' + id);
  }
  const measured = Object.fromEntries(Object.entries(images).map(([id, image]) => [id, measureSectionEdges(image)]));
  const oldNorth = measureEdge(oldMap, 'top');
  if (!oldNorth.road || !oldNorth.water) throw new Error('The existing map north edge must expose its road and river.');
  const riverRoad = meanRoad(measured['01'].top.road, measured['02'].bottom.road);
  const riverShore = (measured['01'].top.water.start + measured['02'].bottom.water.start) / 2;
  const farmRoad = meanRoad(measured['01'].left.road, measured['03'].right.road);
  const tavernRoad = meanRoad(measured['02'].left.road, measured['04'].right.road);
  const footpath = meanRoad(measured['03'].top.road, measured['04'].bottom.road);
  const targets = {
    '01': {bottom: {road: oldNorth.road, shore: oldNorth.water.start}, top: {road: riverRoad, shore: riverShore}, left: {road: farmRoad}},
    '02': {bottom: {road: riverRoad, shore: riverShore}, left: {road: tavernRoad}},
    '03': {right: {road: farmRoad}, top: {road: footpath}},
    '04': {right: {road: tavernRoad}, bottom: {road: footpath}},
  };
  const result = {};
  for (const id of ['01', '02', '03', '04']) result[id] = buildWarp(images[id], measured[id], targets[id]);
  result.measurements = {originalEdges: measured, existingMapNorth: oldNorth, targets, edgeDepth: EDGE_DEPTH, stripDepth: STRIP_DEPTH};
  return result;
}

function applyPixelMap(input, mapping, channels = 4) {
  const map = mapping.map instanceof Int32Array ? mapping.map : mapping;
  const output = Buffer.isBuffer(input) ? Buffer.alloc(map.length * channels) : new input.constructor(map.length * channels);
  for (let dest = 0; dest < map.length; dest++) {
    const src = map[dest] * channels;
    for (let channel = 0; channel < channels; channel++) output[dest * channels + channel] = input[src + channel];
  }
  return output;
}

module.exports = {planSectionWarps, applyPixelMap, measureSectionEdges};
