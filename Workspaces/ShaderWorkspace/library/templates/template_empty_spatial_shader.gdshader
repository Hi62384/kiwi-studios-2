// Empty Spatial Shader
// Minimal valid mesh material with a visible baseline and documented extension points.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
// Add vertex() to deform geometry or light() to customize lighting.
void fragment() {
    // Start with a visible neutral, lit surface.
    ALBEDO=vec3(0.7);
    ROUGHNESS=0.7;
}
