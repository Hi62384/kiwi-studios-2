// Vertex Waves
// Plane waves deform height and analytically update normals; use a subdivided plane.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float amplitude : hint_range(0,1)=0.15;
uniform float frequency : hint_range(0.1,15)=5;
uniform float speed : hint_range(0,8)=2;
void vertex() {
    float phase=VERTEX.x*frequency+TIME*speed;
    VERTEX.y+=sin(phase)*amplitude;
    NORMAL=normalize(vec3(-cos(phase)*frequency*amplitude,1,0));
}
void fragment() {
    ALBEDO=vec3(0.2,0.6,0.5);
    ROUGHNESS=0.55;
}
