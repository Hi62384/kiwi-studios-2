// Shader With Organized Uniform Groups
// Functional animated PBR material demonstrating collapsible inspector uniform groups.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
// Groups appear as collapsible inspector sections.
group_uniforms Appearance;
uniform vec4 base_color : source_color=vec4(0.25,0.55,0.8,1);
uniform float emission : hint_range(0,4)=0.1;
group_uniforms Surface;
uniform float roughness : hint_range(0,1)=0.4;
uniform float metallic : hint_range(0,1)=0.2;
group_uniforms Motion;
uniform float amplitude : hint_range(0,0.5)=0.03;
uniform float speed : hint_range(0,8)=2;
group_uniforms;
void vertex() {
    VERTEX+=NORMAL*sin(TIME*speed)*amplitude;
}
void fragment() {
    ALBEDO=base_color.rgb;
    METALLIC=metallic;
    ROUGHNESS=roughness;
    EMISSION=base_color.rgb*emission;
}
