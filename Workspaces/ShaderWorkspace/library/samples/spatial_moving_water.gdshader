// Moving Water
// Two crossing analytic waves produce moving geometry and correct wave normals on a subdivided plane.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
void vertex() {
    float a=VERTEX.x*4.0+TIME*1.3;
    float b=VERTEX.z*5.0-TIME;
    VERTEX.y+=sin(a)*0.09+sin(b)*0.05;
    NORMAL=normalize(vec3(-cos(a)*0.36,1,-cos(b)*0.25));
}
void fragment() {
    ALBEDO=vec3(0.03,0.29,0.4);
    ROUGHNESS=0.1;
    METALLIC=0.25;
}
