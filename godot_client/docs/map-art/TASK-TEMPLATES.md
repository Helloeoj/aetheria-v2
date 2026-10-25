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

## New area: approved image to playable scene

Follow [PLAYABLE-MAP-PIPELINE.md](PLAYABLE-MAP-PIPELINE.md) in order. Do not skip
the user's whole-map image approval by going straight to kit assembly.

```text
Area / profile / target scene: [id, selected art profile, scene]
Discussion / user references: [requirements and image paths]
Camera / scale: [established angle, native density, world dimensions]
Gameplay grid: 32 world pixels; stable origin [x,y]; art-cell scale [separate]
Layout: [landmarks, room flow, entrances/exits, planned interaction approaches]
Candidate / approved master: [exact versions/paths; approval evidence or pending]
Decomposition: [ground layers; individual reusable props; missing hidden parts]
Reuse / missing pieces: [selected asset IDs; genuinely needed generation]
Prop records: [canvas, foot anchor, world placement, sorting, collision base]
Path validation: [full-body clearance, swept edges, corners, narrow routes]
Interaction / transition validation: [reachable centers, ranges, safe arrivals]
Runtime validation: [WASD/click input, enemy/chase, offline/online, visual review]
Status: [image review, scene installation, gameplay validation tracked separately]
Changed files / holds / next action: [scoped handoff]
```

Reuse existing pieces in the approved composition; keep ground, props, collision
and actors separate. Match neighboring ground/exits. Do not flatten an assembled
area and re-extract objects that already exist separately. Existing-map local
repairs retain their bounded workflow rather than restarting area generation.

## Cheap handoff

End each task record with changed files, remaining visual issues and the next action. Optionally record generation attempts, credits actually reported by the service and time spent. Use measured usage only; do not invent token savings.
