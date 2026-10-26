// World Aligned Texturing
// Top-down world-space projection keeps a shared pattern aligned across separate meshes.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture=false;
uniform float texture_scale : hint_range(0.1,20)=4;
varying vec3 world_pos;
varying vec3 world_normal;
vec3 checker(vec2 uv) {
    return mix(vec3(0.12,0.2,0.3),vec3(0.65,0.8,0.86),mod(floor(uv.x)+floor(uv.y),2.0));
}
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec2 p=world_pos.xz*texture_scale;
    ALBEDO=use_texture?texture(source_texture,p).rgb:checker(p);
    ROUGHNESS=0.7;
}
