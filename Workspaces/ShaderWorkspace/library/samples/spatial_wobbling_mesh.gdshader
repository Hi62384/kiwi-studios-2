// Wobbling Mesh
// Cross-axis traveling bends create a jelly-like deforming mesh.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float amount : hint_range(0,0.5)=0.15;
void vertex() {
    VERTEX.x+=sin(VERTEX.y*5.0+TIME*3.0)*amount;
    VERTEX.z+=cos(VERTEX.y*4.0+TIME*2.5)*amount;
}
void fragment() {
    ALBEDO=vec3(0.3,0.55,0.9);
    ROUGHNESS=0.25;
}
