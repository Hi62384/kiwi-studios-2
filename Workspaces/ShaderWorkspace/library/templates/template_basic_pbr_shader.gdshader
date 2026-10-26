// Basic PBR Shader
// Standard physically based surface inputs organized for rapid material authoring.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.22,0.58,0.72,1);
uniform float roughness : hint_range(0,1)=0.45;
uniform float metallic : hint_range(0,1)=0;
void fragment() {
    // Surface inputs are linear; source_color uniforms are converted by Godot.
    ALBEDO=base_color.rgb;
    METALLIC=metallic;
    ROUGHNESS=roughness;
}
