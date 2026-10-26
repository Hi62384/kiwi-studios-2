// Emission
// Self-lit emissive material; enable environment glow to add a bloom halo.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 color : source_color=vec4(0.2,0.9,0.65,1);
uniform float energy : hint_range(0,12)=3;
void fragment() {
    ALBEDO=color.rgb*0.15;
    EMISSION=color.rgb*energy;
    ROUGHNESS=0.6;
}
