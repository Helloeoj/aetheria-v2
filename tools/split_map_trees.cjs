'use strict';

// A flattened vegetation layer can join otherwise separate trees wherever their
// canopies touch. Give each tree its own sorting pivot without changing, copying,
// or dropping any source pixel. The visible artwork cannot recover foliage that
// was hidden by another tree, so these are partitions of the approved composite.
//
// The six measured crown envelopes below describe the three joined pairs in the
// original outskirts. Elliptical crown distance makes the shared boundary follow
// the crown shapes rather than a straight cut halfway between the trunks. Narrow
// stem envelopes keep exposed trunk pixels with their authored collision anchor.
const AUTHORED_CROWNS = new Map([
  ['530,207', { centerY: 91, radiusX: 134, radiusY: 108 }],
  ['627,257', { centerY: 192, radiusX: 82, radiusY: 64 }],
  ['260,196', { centerY: 171, radiusX: 31, radiusY: 29 }],
  ['255,283', { centerY: 234, radiusX: 45, radiusY: 43 }],
  ['444,940', { centerY: 801, radiusX: 134, radiusY: 116 }],
  ['577,992', { centerY: 932, radiusX: 66, radiusY: 60 }],
]);

function anchorPoint(anchor) {
  const point = Array.isArray(anchor) ? anchor : anchor.position;
  if (!Array.isArray(point) || point.length !== 2 || !point.every(Number.isFinite)) {
    throw new TypeError('Tree anchors must be [x, y] or { position: [x, y] }.');
  }
  return point;
}

function modelFor(anchor, component, count) {
  const point = anchorPoint(anchor);
  const measured = AUTHORED_CROWNS.get(point.join(','));
  const supplied = !Array.isArray(anchor) ? anchor.crown : null;
  const radiusX = Math.max(16, component.w / Math.max(1.5, count));
  const radiusY = Math.max(18, Math.min(component.h * 0.4, radiusX));
  const crown = supplied || measured || {
    centerY: point[1] - radiusY * 1.12,
    radiusX,
    radiusY,
  };
  return { point, ...crown };
}

function assignmentCost(x, y, model) {
  const dx = x - model.point[0];
  const dy = y - model.centerY;
  let cost = (dx / model.radiusX) ** 2 + (dy / model.radiusY) ** 2;
  const stemTop = model.centerY + model.radiusY * 0.6;
  if (y >= stemTop) {
    const stemBottom = model.point[1] + 3;
    const outsideY = Math.max(stemTop - y, 0, y - stemBottom);
    const stemWidth = Math.max(4, model.radiusX * 0.11);
    const stemCost = (dx / stemWidth) ** 2 + (outsideY / 8) ** 2;
    cost = Math.min(cost, stemCost);
  }
  return cost;
}

/**
 * Split one connected alpha component using the authored trunk anchors it owns.
 *
 * @param {{pixels:number[],minX:number,maxX:number,minY:number,maxY:number,w:number,h:number}} component
 * @param {(number[]|{position:number[],crown?:object})[]} anchors Candidate world-space anchors.
 * @param {number} width Source image width; component pixels are row-major indices.
 * @returns {object[]} Components with the usual bounds, pixels, and an explicit anchor.
 *
 * Unanchored edge forest and single trees pass through unchanged. A caller can
 * retain its existing size classifier; returned parts also carry sourceComponent
 * so that a narrow partition does not have to be discarded as ground detail.
 */
function splitTreeComponent(component, anchors, width) {
  if (!Number.isInteger(width) || width <= 0) throw new TypeError('Image width must be a positive integer.');
  const owned = anchors.filter(anchor => {
    const [x, y] = anchorPoint(anchor);
    return x >= component.minX - 12 && x <= component.maxX + 12
      && y >= component.minY && y <= component.maxY + 18;
  });
  if (owned.length === 0) return [component];
  if (owned.length === 1) return [{ ...component, anchor: [...anchorPoint(owned[0])] }];

  // Stable order resolves exact ties in favor of the tree nearer the viewer.
  const models = owned.map(anchor => modelFor(anchor, component, owned.length))
    .sort((a, b) => b.point[1] - a.point[1] || a.point[0] - b.point[0]);
  const bins = models.map(model => ({
    pixels: [], minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity,
    anchor: [...model.point], sourceComponent: component,
  }));
  for (const pixel of component.pixels) {
    const x = pixel % width;
    const y = Math.floor(pixel / width);
    let selected = 0;
    let bestCost = Infinity;
    for (let index = 0; index < models.length; index++) {
      const cost = assignmentCost(x, y, models[index]);
      if (cost < bestCost) {
        selected = index;
        bestCost = cost;
      }
    }
    const bin = bins[selected];
    bin.pixels.push(pixel);
    bin.minX = Math.min(bin.minX, x);
    bin.maxX = Math.max(bin.maxX, x);
    bin.minY = Math.min(bin.minY, y);
    bin.maxY = Math.max(bin.maxY, y);
  }
  return bins.filter(bin => bin.pixels.length > 0).map(bin => ({
    ...bin, w: bin.maxX - bin.minX + 1, h: bin.maxY - bin.minY + 1,
  }));
}

module.exports = { splitTreeComponent };
