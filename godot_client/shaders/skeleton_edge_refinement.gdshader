// Approved skeleton edge smoothing: select existing neighboring colors only.
// Scale2x corner rules, https://www.scale2x.it/algorithm . No blur or redraw.
shader_type canvas_item;
varying vec4 vertex_modulation;

void vertex() {
	vertex_modulation = COLOR;
}

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	vec2 center = (floor(pixel) + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
	vec2 low = TEXTURE_PIXEL_SIZE * 0.5;
	vec2 high = vec2(1.0) - low;
	vec4 e = texture(TEXTURE, clamp(center, low, high));
	vec4 b = texture(TEXTURE, clamp(center - vec2(0.0, TEXTURE_PIXEL_SIZE.y), low, high));
	vec4 d = texture(TEXTURE, clamp(center - vec2(TEXTURE_PIXEL_SIZE.x, 0.0), low, high));
	vec4 f = texture(TEXTURE, clamp(center + vec2(TEXTURE_PIXEL_SIZE.x, 0.0), low, high));
	vec4 h = texture(TEXTURE, clamp(center + vec2(0.0, TEXTURE_PIXEL_SIZE.y), low, high));
	vec4 result = e;
	if (any(notEqual(b, h)) && any(notEqual(d, f))) {
		if (fract(pixel.y) < 0.5) {
			if (fract(pixel.x) < 0.5 && all(equal(d, b))) { result = d; }
			if (fract(pixel.x) >= 0.5 && all(equal(b, f))) { result = f; }
		} else {
			if (fract(pixel.x) < 0.5 && all(equal(d, h))) { result = d; }
			if (fract(pixel.x) >= 0.5 && all(equal(h, f))) { result = f; }
		}
	}
	COLOR = result * vertex_modulation;
}
