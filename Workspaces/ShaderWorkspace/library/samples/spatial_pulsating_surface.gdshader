// Pulsating Surface
// Uniform normal expansion and contraction creates a breathing or charging surface.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float amplitude : hint_range(0,0.5)=0.13;
uniform float speed : hint_range(0,10)=3;
void vertex() {
    VERTEX+=NORMAL*sin(TIME*speed)*amplitude;
}
void fragment() {
    ALBEDO=vec3(0.5,0.12,0.32);
    ROUGHNESS=0.3;
}
