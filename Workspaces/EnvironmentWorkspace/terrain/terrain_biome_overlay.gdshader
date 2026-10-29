shader_type spatial;
render_mode unshaded,depth_draw_never;
uniform sampler2D weights:filter_linear_mipmap,repeat_disable;
uniform vec2 terrain_size=vec2(32.0);
uniform vec4 tint:source_color=vec4(0.2,0.8,0.6,1.0);
varying vec2 map_uv;
void vertex(){map_uv=VERTEX.xz/terrain_size+vec2(0.5);}
void fragment(){ALBEDO=tint.rgb;ALPHA=clamp(texture(weights,map_uv).r,0.0,1.0)*0.6;}
