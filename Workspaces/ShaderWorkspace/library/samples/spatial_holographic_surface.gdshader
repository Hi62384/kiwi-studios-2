// Holographic Surface
// View-angle interference colors create iridescent holographic foil.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
void fragment() {
    float f=1.0-max(dot(NORMAL,VIEW),0.0);
    vec3 spectrum=0.5+0.5*cos(TAU*(f*2.0+TIME*0.06+vec3(0,0.33,0.67)));
    ALBEDO=spectrum;
    METALLIC=0.8;
    ROUGHNESS=0.2;
    EMISSION=spectrum*0.15;
}
