// Crystal
// Faceted color bands and luminous internal edges suggest a polished fantasy crystal.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode diffuse_burley;
void fragment() {
    float facet=floor(UV.x*8.0)/8.0;
    float rim=pow(1.0-max(dot(NORMAL,VIEW),0.0),3.0);
    ALBEDO=mix(vec3(0.12,0.08,0.35),vec3(0.5,0.75,1),facet);
    EMISSION=vec3(0.25,0.3,0.8)*rim;
    METALLIC=0.5;
    ROUGHNESS=0.12;
}
