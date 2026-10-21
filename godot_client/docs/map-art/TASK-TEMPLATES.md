# Small task records and prompts

Copy the relevant brief into one task folder under the supporting workspace's `work/map-planning/tasks/<task-id>/`. Bracketed fields are intentional template fields, not current instructions to generate or install artwork.

## Local repair brief

```text
Task / profile: [id] / [valtheiris-overworld or golem-kingdom-detail4x]
Requested change: [one concrete visual defect or improvement]
Stage authorized: [preview only / install within the requested scope]
World rectangle: [x, y, width, height; half-open bounds]
Image rectangle + mapping: [crop size, world origin, pixels per world unit]
Allowed layers/assets: [exact names/paths]
Reuse IDs: [ASSET-INDEX entries]
References: [target first, then 1–2 saved style images]
Preserve: [geometry, routes, shoreline, objects, anchors, alpha, outside pixels]
Context border: [pixels visible around the editable mask, excluded from edits]
Result: [source path, prompt/settings/job ID if any, attempts, selected output]
Review / installation: [separate statuses; evidence paths]
Next action: [one concrete step]
```

Generation prompt, only if reuse cannot solve the task:

```text
Edit image 1 only inside [mask/rectangle] to [requested change]. Images 2–3
guide style only. Match the saved [profile] art specification and existing
pixel density, perspective, palette and lighting. Preserve [fixed features]
and all pixels outside the allowed region. Keep the context border intact.
Terrain only; existing props are separate. No characters, creatures, NPCs,
enemies, golems, animals, character sprites, text, grid or baked ground shadows.
```

Keep the original outside-mask pixels during assembly even if generation drifts. Reject a candidate with changed geography inside the mask when geography was meant to stay fixed. Do not compensate by stretching or warping the art.

## Missing reusable object brief

```text
Need: [object type and number genuinely missing after checking the index]
Profile / reference: [profile, one complete existing object]
Native canvas / foot anchor: [width, height / x, y]
Physical size: [intended world footprint; separate from canvas dimensions]
Output: one complete transparent PNG per object, exact generation provenance,
reviewed anchor, light/dark/ground preview. Preserve originals.
Sample first: one representative asset; expand only if it meets the brief.
```

Object prompt: “One complete [object], matching the supplied reference's camera, pixel density, palette and lighting. Transparent background, complete silhouette, internal shading. No ground mat, cast shadow, clipped parts, neighboring objects, characters or creatures. Canvas [W × H].”

## New area assembled from a kit

Record the target scene, origin/size, road/river exits at each edge, selected terrain/object IDs, walkable routes and landmarks. Assemble a preview from existing pieces first. Keep terrain, objects, collision and actors separate. List missing assets explicitly before generating them. Match neighboring ground and exits; do not flatten an assembled area and then re-extract its objects.

## Cheap handoff

End each task record with changed files, remaining visual issues and the next action. Optionally record generation attempts, credits actually reported by the service and time spent. Use measured usage only; do not invent token savings.
