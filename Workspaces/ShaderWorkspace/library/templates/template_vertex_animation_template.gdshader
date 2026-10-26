// Vertex Animation Template
// Structured local-space vertex motion with separate direction, frequency, speed and amplitude.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec3 direction=vec3(0,1,0);
uniform float frequency : hint_range(0,20)=5;
uniform float speed : hint_range(0,10)=2;
uniform float amplitude : hint_range(0,0.5)=0.1;
void vertex() {
    // Keep deformations in local space. Increase mesh subdivisions for smooth results.
    vec3 rest_position=VERTEX;
    float phase=dot(rest_position,direction)*frequency+TIME*speed;
    VERTEX+=NORMAL*sin(phase)*amplitude;
}
void fragment() {
    ALBEDO=vec3(0.3,0.6,0.75);
    ROUGHNESS=0.5;
}
