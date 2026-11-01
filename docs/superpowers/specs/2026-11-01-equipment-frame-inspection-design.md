# Equipment frame inspection

Resume the rejected armor work by making visual inspection dependable first.
Extend the existing F7 SpritePreview; keep its character, direction, equipment,
hit, target and spawn controls. Do not install another armor correction here.

Add pause/resume, previous/next frame with wraparound, a frame counter, integer
1x/3x/4x zoom, a synchronized unarmored reference and lossless PNG export. Pause
both the ActorSprite action clock and AnimatedSprite playback. Direction/action
changes restart at frame zero while remaining paused; equipment changes retain
the current frame. The reference uses the same original skin, frame and anchor.
Export the actual rendered preview with a JSON record of pose and equipment.

Alternatives: a separate sprite editor would duplicate runtime behavior; GIF
previews obscure individual frames and quantize colors. Extending F7 directly
uses the actual actor and attachment rig. This is the implementation choice.

Review at 1x and 4x: neck/waist continuity, attached limbs, face and skin colors,
foot contact, weapon grips and adjacent-frame consistency. Tests establish tool
behavior only. Existing armor remains unapproved if any visible defect remains.
