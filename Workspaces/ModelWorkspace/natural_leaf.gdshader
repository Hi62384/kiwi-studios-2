shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec4 leaf_color:source_color=vec4(.14,.38,.055,1.);
uniform float wind_strength:hint_range(0.,1.)=0.;
uniform float wind_speed=1.;
varying float variation;
void vertex(){
	variation=sin(dot(VERTEX,vec3(12.9898,7.233,5.2)))*.5+.5;
	float phase=TIME*wind_speed+VERTEX.x*.7+VERTEX.z*.5;
	float weight=UV.y*UV.y;
	VERTEX.xz+=vec2(sin(phase),cos(phase*.83))*wind_strength*weight*.12;
}
void fragment(){
	ALBEDO=leaf_color.rgb*mix(.83,1.13,variation);
	ROUGHNESS=.85;
	BACKLIGHT=leaf_color.rgb*.3;
}
