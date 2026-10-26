// Normal Mapping
// Tangent-space normal mapping with a working procedural embossed tile fallback.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D normal_texture : hint_normal,repeat_enable;
uniform bool use_texture=false;
uniform float strength : hint_range(0,1)=0.35;
uniform float tiles : hint_range(1,20)=8;
void fragment() {
    ALBEDO=vec3(0.4,0.62,0.76);
    vec2 wave=cos(UV*TAU*tiles)*strength;
    NORMAL_MAP=use_texture?texture(normal_texture,UV*tiles).rgb:normalize(vec3(wave,1))*0.5+0.5;
    ROUGHNESS=0.3;
}
