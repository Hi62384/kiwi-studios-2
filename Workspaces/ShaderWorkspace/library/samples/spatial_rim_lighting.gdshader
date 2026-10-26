// Rim Lighting
// Luminous grazing-angle edge light adds readable silhouettes against dark scenes.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 rim_color : source_color=vec4(0.1,0.7,1,1);
uniform float power : hint_range(0.2,10)=3;
uniform float strength : hint_range(0,5)=2;
void fragment() {
    float r=pow(1.0-max(dot(NORMAL,VIEW),0.0),power);
    ALBEDO=vec3(0.1,0.18,0.26);
    EMISSION=r*rim_color.rgb*strength;
    ROUGHNESS=0.5;
}
