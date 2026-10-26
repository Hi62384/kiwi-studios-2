// Shield Effect
// Expanding impact ring travels over a transparent energy shield.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled;
uniform vec2 hit_uv=vec2(0.5);
void fragment() {
    float r=length(UV-hit_uv);
    float ring=exp(-pow((r-fract(TIME*0.4)*0.7)*45.0,2.0));
    float f=pow(1.0-max(dot(NORMAL,VIEW),0.0),3.0);
    ALBEDO=vec3(0.05,0.2,0.45);
    EMISSION=vec3(0.15,0.65,1)*(ring*3.0+f);
    ALPHA=clamp(0.08+f*0.5+ring*0.7,0.0,1.0);
}
