// Metallic Surface
// Conductive gold-like metal with tinted reflections and an optional clear finish.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 metal_color : source_color=vec4(0.83,0.61,0.26,1);
uniform float roughness : hint_range(0.02,1)=0.18;
void fragment() {
    ALBEDO=metal_color.rgb;
    METALLIC=1.0;
    ROUGHNESS=roughness;
    CLEARCOAT=0.6;
    CLEARCOAT_ROUGHNESS=0.2;
}
