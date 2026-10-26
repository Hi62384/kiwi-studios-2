// Vertex Color Material
// Reads per-vertex colors for painted meshes, imported assets and GPU particle draw passes.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 tint : source_color=vec4(0.4,0.85,0.6,1);
uniform float roughness : hint_range(0,1)=0.75;
void fragment() {
    ALBEDO=COLOR.rgb*tint.rgb;
    ROUGHNESS=roughness;
}
