// Force Field
// Transparent grazing-angle shell with an emissive latitude-longitude grid.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled;
void fragment() {
    float f=pow(1.0-max(dot(NORMAL,VIEW),0.0),2.5);
    vec2 p=UV*vec2(24,12);
    float grid=min(abs(fract(p.x)-0.5),abs(fract(p.y)-0.5));
    float line=1.0-smoothstep(0.02,0.06,grid);
    ALBEDO=vec3(0.05,0.45,0.8);
    EMISSION=vec3(0.05,0.6,1)*(f*2.0+line*0.6);
    ALPHA=clamp(f+line*0.2,0.08,0.85);
}
