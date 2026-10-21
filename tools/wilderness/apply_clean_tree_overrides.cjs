'use strict';

// Restore explicitly reviewed artwork after archival image reconstruction.
// This helper writes PNGs only. It never reads or rewrites map scene geometry.
const fs = require('node:fs');
const path = require('node:path');

const REGISTRY = 'res://Assets/MapTiles/CleanTrees/overrides.json';
const SOURCE_PREFIX = 'res://Assets/MapTiles/CleanTrees/Overrides/';
const GROUND_SOURCE = 'res://Assets/MapTiles/CleanTrees/Terrain/Grass.png';
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const TREE_TARGETS = [
 /^res:\/\/Assets\/MapTiles\/Objects\/(?:Outskirts|Harbor)_Trees_\d+\.png$/,
 /^res:\/\/Assets\/MapTiles\/Wilderness\/PolishedObjects\/Border_Outskirts_Trees_\d+_Complete\.png$/,
 /^res:\/\/Assets\/MapTiles\/Wilderness\/PolishedObjects\/Outskirts_Trees_\d+_s\d+\.png$/,
];

function isInside(parent, child) {
 const relative = path.relative(parent, child);
 return relative !== '' && relative !== '..'
  && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative);
}

function resourceFile(projectRoot, resource) {
 if (typeof resource !== 'string' || !resource.startsWith('res://')
  || resource.includes('\\') || resource.includes('\0')) {
  throw new Error('Invalid reviewed-art resource path: ' + String(resource));
 }
 const relative = resource.slice(6);
 if (relative.split('/').some(part => part === '' || part === '.' || part === '..')) {
  throw new Error('Reviewed-art path must be project-relative without traversal: ' + resource);
 }
 const resolved = path.resolve(projectRoot, relative);
 if (!isInside(projectRoot, resolved)) {
  throw new Error('Reviewed-art path escaped the project: ' + resource);
 }
 if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
  throw new Error('Reviewed-art file is missing: ' + resource);
 }
 const real = fs.realpathSync(resolved);
 if (!isInside(projectRoot, real)) {
  throw new Error('Reviewed-art symlink escaped the project: ' + resource);
 }
 return real;
}

function pngSize(buffer, resource) {
 if (buffer.length < 33 || !buffer.subarray(0, 8).equals(PNG_SIGNATURE)
  || buffer.readUInt32BE(8) !== 13 || buffer.toString('ascii', 12, 16) !== 'IHDR') {
  throw new Error('Reviewed-art file is not a PNG with an IHDR header: ' + resource);
 }
 const size = [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
 if (size.some(value => value < 1)) throw new Error('PNG has an empty canvas: ' + resource);
 return size;
}

// Returns registered (validated entries), applied (PNG files whose bytes were
// replaced), unchanged (already identical PNGs), and missing_registry. A missing
// registry is a no-op for projects which have not installed reviewed artwork.
function applyCleanTreeOverrides(options = {}) {
 const projectRoot = fs.realpathSync(options.projectRoot || path.resolve(__dirname, '../../godot_client'));
 const registryResource = options.registryResource || REGISTRY;
 if (registryResource !== REGISTRY) {
  throw new Error('Only the reviewed tree-art override registry is supported.');
 }
 const registryPath = path.resolve(projectRoot, registryResource.slice(6));
 if (!fs.existsSync(registryPath)) {
  return {registry: registryResource, registered: 0, applied: 0, unchanged: 0, missing_registry: true};
 }
 const manifest = JSON.parse(fs.readFileSync(resourceFile(projectRoot, registryResource), 'utf8'));
 if (!manifest || !Array.isArray(manifest.overrides)) {
  throw new Error('Reviewed-art override registry must contain an overrides array.');
 }
 const prepared = [];
 const targets = new Set();
 // Validate the complete registry before changing any referenced image.
 for (const entry of manifest.overrides) {
  if (!entry || typeof entry !== 'object' || typeof entry.target !== 'string'
   || typeof entry.texture !== 'string') {
   throw new Error('Reviewed-art override requires target and texture resource paths.');
  }
  const allowedTree = TREE_TARGETS.some(pattern => pattern.test(entry.target));
  const allowedGround = entry.target === 'res://Assets/MapTiles/Grass.png';
  if (!allowedTree && !allowedGround) {
   throw new Error('Override target is outside reviewed tree/grass artwork: ' + entry.target);
  }
  const allowedSource = allowedGround ? entry.texture === GROUND_SOURCE
   : entry.texture.startsWith(SOURCE_PREFIX) && entry.texture.endsWith('.png')
    && path.posix.basename(entry.texture) === path.posix.basename(entry.target);
  if (!allowedSource) {
   throw new Error('Override source must be its matching reviewed PNG: ' + entry.texture);
  }
  if (!Array.isArray(entry.size) || entry.size.length !== 2
   || !entry.size.every(value => Number.isInteger(value) && value > 0)) {
   throw new Error('Override size must contain two positive integer pixels: ' + entry.target);
  }
  const source = resourceFile(projectRoot, entry.texture);
  const target = resourceFile(projectRoot, entry.target);
  const targetKey = process.platform === 'win32' ? target.toLowerCase() : target;
  if (targets.has(targetKey)) throw new Error('Duplicate reviewed-art target: ' + entry.target);
  targets.add(targetKey);
  if (source === target) throw new Error('Reviewed source and target cannot be the same file.');
  const sourceBytes = fs.readFileSync(source);
  const targetBytes = fs.readFileSync(target);
  for (const [bytes, resource] of [[sourceBytes, entry.texture], [targetBytes, entry.target]]) {
   const actual = pngSize(bytes, resource);
   if (actual.some((value, index) => value !== entry.size[index])) {
    throw new Error('Reviewed PNG canvas differs from its registered size: ' + resource);
   }
  }
  prepared.push({target, resource: entry.target, bytes: sourceBytes, changed: !targetBytes.equals(sourceBytes)});
 }
 let applied = 0;
 for (const entry of prepared) {
  if (!entry.changed) continue;
  fs.writeFileSync(entry.target, entry.bytes);
  applied++;
 }
 return {
  registry: registryResource,
  registered: prepared.length,
  applied,
  unchanged: prepared.length - applied,
  missing_registry: false,
 };
}

module.exports = {applyCleanTreeOverrides};

if (require.main === module) {
 try {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--project')) {
   throw new Error('Usage: node apply_clean_tree_overrides.cjs [--project godot_client]');
  }
  const result = applyCleanTreeOverrides(args.length ? {projectRoot: args[1]} : {});
  console.log(JSON.stringify(result, null, 2));
 } catch (error) {
  console.error(error.stack);
  process.exitCode = 1;
 }
}
