shader_type spatial;

uniform float strength : hint_range(0.0, 4.0, 0.1) = 1.0;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D mask_texture;

void fragment() {
	ALBEDO = tint;
	EMISSION = glow_color.rgb * strength;
}
