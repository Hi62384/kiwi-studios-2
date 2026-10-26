// Textured PBR Shader
// Optional albedo texture with a procedural fallback and independent surface controls.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture=false;
uniform float texture_scale : hint_range(0.1,20)=4;
uniform float roughness : hint_range(0,1)=0.6;
uniform float metallic : hint_range(0,1)=0;
vec3 checker(vec2 uv) {
    return mix(vec3(0.12,0.2,0.3),vec3(0.65,0.8,0.86),mod(floor(uv.x)+floor(uv.y),2.0));
}
void fragment() {
    vec2 uv=UV*texture_scale;
    // Enable the optional slot after assigning a texture. Fallback always works.
    ALBEDO=use_texture?texture(source_texture,uv).rgb:checker(uv);
    ROUGHNESS=roughness;
    METALLIC=metallic;
}
