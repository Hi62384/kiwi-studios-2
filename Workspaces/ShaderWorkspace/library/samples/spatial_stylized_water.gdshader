// Stylized Water
// Opaque cartoon water with crest foam and animated surface normals.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
void fragment() {
    float wave=sin(UV.x*30.0+TIME)*sin(UV.y*24.0-TIME);
    float foam=smoothstep(0.72,0.9,wave);
    ALBEDO=mix(vec3(0.015,0.2,0.33),vec3(0.15,0.7,0.75),wave*0.5+0.5)+foam*0.6;
    ROUGHNESS=0.18;
    NORMAL_MAP=normalize(vec3(cos(UV.x*30.0+TIME)*0.15,sin(UV.y*24.0-TIME)*0.15,1))*0.5+0.5;
}
