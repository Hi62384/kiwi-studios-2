// Basic PBR Material
// A complete lit surface with editable albedo, metallic response and roughness.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.22,0.58,0.72,1);
uniform float roughness : hint_range(0,1)=0.45;
uniform float metallic : hint_range(0,1)=0;
void fragment() {
    ALBEDO=base_color.rgb;
    ROUGHNESS=roughness;
    METALLIC=metallic;
}
