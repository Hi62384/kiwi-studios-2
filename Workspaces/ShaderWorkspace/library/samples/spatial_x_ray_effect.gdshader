// X Ray Effect
// Depth-test-disabled transparent overlay shows a mesh through occluders; use as a dedicated overlay.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode unshaded,depth_test_disabled,cull_disabled;
void fragment() {
    float f=pow(1.0-abs(dot(NORMAL,VIEW)),2.0);
    ALBEDO=vec3(0.08,0.55,0.8);
    EMISSION=vec3(0.1,0.7,1)*(0.2+f);
    ALPHA=0.1+f*0.65;
}
