// Bending Vegetation
// Height-weighted bending for branches and stems; base remains anchored.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float strength : hint_range(0,0.5)=0.12;
uniform float speed : hint_range(0,4)=1.1;
void vertex() {
    float h=max(VERTEX.y+1.0,0.0);
    float bend=sin(TIME*speed)*strength;
    VERTEX.x+=h*h*bend;
    NORMAL=normalize(NORMAL+vec3(0,-2.0*h*bend*NORMAL.x,0));
}
void fragment() {
    ALBEDO=vec3(0.19,0.35,0.07);
    ROUGHNESS=0.85;
}
