shader_type canvas_item;

uniform sampler2D color_lookup : filter_nearest, repeat_disable;
uniform float edge_strength : hint_range(0.0, 2.0) = 0.65;
uniform float ink_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ink_threshold : hint_range(0.15, 0.5) = 0.40;
uniform float palette_strength : hint_range(0.0, 1.0) = 1.0;
uniform float denoise_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ink_hardness : hint_range(0.0, 1.0) = 1.0;
varying vec4 artwork_modulate;

void vertex() { artwork_modulate = COLOR; }

vec3 covered_color(vec4 sampled, vec3 center) {
	return mix(center, sampled.rgb, step(0.99, sampled.a));
}
float luma(vec3 color) { return dot(color, vec3(0.2126, 0.7152, 0.0722)); }
float similarity(vec3 a, vec3 b) {
	vec3 delta = abs(a - b);
	return 1.0 - smoothstep(0.025, 0.10, max(max(delta.r, delta.g), delta.b));
}

void fragment() {
	vec4 center = texture(TEXTURE, UV);
	vec2 source_rate=fwidth(UV)/TEXTURE_PIXEL_SIZE;
	float screen_texel=1.0/max(max(source_rate.x,source_rate.y),0.001);
	float zoom_weight=smoothstep(0.5,1.15,screen_texel);
	COLOR=center*artwork_modulate;
	// Skip the neighborhood pass when a source texel is too small to display.
	// Derivatives are evaluated before this branch so adjacent texels agree.
	if (zoom_weight > 0.001) {
	vec2 p = TEXTURE_PIXEL_SIZE;
	vec3 n = covered_color(texture(TEXTURE, UV + vec2(0.0, -p.y)), center.rgb);
	vec3 s = covered_color(texture(TEXTURE, UV + vec2(0.0, p.y)), center.rgb);
	vec3 w = covered_color(texture(TEXTURE, UV + vec2(-p.x, 0.0)), center.rgb);
	vec3 e = covered_color(texture(TEXTURE, UV + vec2(p.x, 0.0)), center.rgb);
	vec3 nw = covered_color(texture(TEXTURE, UV - p), center.rgb);
	vec3 ne = covered_color(texture(TEXTURE, UV + vec2(p.x, -p.y)), center.rgb);
	vec3 sw = covered_color(texture(TEXTURE, UV + vec2(-p.x, p.y)), center.rgb);
	vec3 se = covered_color(texture(TEXTURE, UV + p), center.rgb);
	float wn=similarity(center.rgb,n), ws=similarity(center.rgb,s), ww=similarity(center.rgb,w), we=similarity(center.rgb,e);
	float wnw=similarity(center.rgb,nw), wne=similarity(center.rgb,ne), wsw=similarity(center.rgb,sw), wse=similarity(center.rgb,se);
	vec3 smooth_color = (center.rgb*2.0+n*wn+s*ws+w*ww+e*we+nw*wnw+ne*wne+sw*wsw+se*wse)
		/ (2.0+wn+ws+ww+we+wnw+wne+wsw+wse);
	vec3 base = mix(center.rgb, smooth_color, denoise_strength);
	vec3 lo=min(center.rgb,min(min(n,s),min(w,e)));
	vec3 hi=max(center.rgb,max(max(n,s),max(w,e)));
	float low=luma(lo), high=luma(hi), contrast=high-low;
	float edge=smoothstep(0.065,0.18,contrast);
	vec3 crisp=clamp(base+(base-(n+s+w+e)*0.25)*edge_strength*edge,lo,hi);
	float value=luma(crisp);
	float position=(value-low)/max(contrast,0.001);
	float chroma=max(max(crisp.r,crisp.g),crisp.b)-min(min(crisp.r,crisp.g),crisp.b);
	float ink=(1.0-smoothstep(0.10,0.16,low))*smoothstep(0.16,0.28,contrast)
		*(1.0-smoothstep(ink_threshold-0.06,ink_threshold+0.06,position))
		*(1.0-smoothstep(0.25,0.45,chroma));
	float decisive_ink=step(low,0.13)*step(0.20,contrast)*step(position,ink_threshold)
		*(1.0-smoothstep(0.25,0.45,chroma));
	ink=mix(ink,decisive_ink,ink_hardness);
	crisp=mix(crisp,vec3(0.0),ink*ink_strength);
	vec3 cell=floor(clamp(crisp,vec3(0.0),vec3(1.0))*31.0+0.5);
	vec2 lookup_uv=(vec2(cell.r+cell.b*32.0,cell.g)+vec2(0.5))/vec2(1024.0,32.0);
	vec3 palette_color=texture(color_lookup,lookup_uv).rgb;
	crisp=mix(crisp,palette_color,palette_strength);
	// At the farthest zoom the source texel is subpixel. Fade the extra edge
	// contrast there to keep the original smooth, stable distant silhouettes.
	COLOR=vec4(mix(center.rgb,crisp,zoom_weight),center.a)*artwork_modulate;
	}
}
