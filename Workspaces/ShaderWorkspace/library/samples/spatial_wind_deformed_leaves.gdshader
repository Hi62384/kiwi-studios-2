// Wind Deformed Leaves
// Higher frequency normal flutter gives foliage a leaf-like tremble independent of branch sway.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float strength : hint_range(0,0.5)=0.09;
void vertex() {
    float flex=sin(TIME*3.5+VERTEX.x*6.0+VERTEX.z*4.0);
    VERTEX+=NORMAL*flex*strength*(0.3+UV.y*0.7);
}
void fragment() {
    ALBEDO=mix(vec3(0.06,0.2,0.015),vec3(0.4,0.55,0.07),UV.y);
    ROUGHNESS=0.8;
}
