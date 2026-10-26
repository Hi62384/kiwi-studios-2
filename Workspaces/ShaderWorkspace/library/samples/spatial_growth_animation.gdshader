// Growth Animation
// Bottom-anchored growth scales height and girth; animate growth from zero to one.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float growth : hint_range(0,1)=0.65;
void vertex() {
    float g=clamp(growth,0.001,1.0);
    VERTEX.y=(VERTEX.y+1.0)*g-1.0;
    VERTEX.xz*=sqrt(g);
}
void fragment() {
    ALBEDO=mix(vec3(0.1,0.25,0.025),vec3(0.4,0.6,0.1),UV.y);
    ROUGHNESS=0.75;
}
