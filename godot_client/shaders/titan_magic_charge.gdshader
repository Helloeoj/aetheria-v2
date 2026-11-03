shader_type canvas_item;
uniform float charge : hint_range(0.0,1.0) = 0.0;
uniform float canvas_height = 256.0;
uniform float source_y_offset = 0.0;
void fragment(){
	vec4 sample_color=texture(TEXTURE,UV);
	// Cyan upper-body crystal light turns violet during casting; restraints
	// below the belt and the original red eyes retain their source colors.
	float crystal=step(sample_color.r+0.12,sample_color.b)*step(sample_color.r+0.10,sample_color.g);
	float upper=1.0-step((153.0+source_y_offset)/canvas_height,UV.y);
	vec3 violet=vec3(0.64,0.17,0.95)*max(0.45,max(sample_color.r,max(sample_color.g,sample_color.b)));
	sample_color.rgb=mix(sample_color.rgb,violet,crystal*upper*charge*0.86);
	COLOR=sample_color;
}
