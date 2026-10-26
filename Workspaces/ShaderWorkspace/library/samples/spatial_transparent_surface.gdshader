// Transparent Surface
// Simple alpha-blended surface for transparent props and overlays.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled,depth_draw_always;
uniform vec4 tint : source_color=vec4(0.15,0.65,0.8,1);
uniform float opacity : hint_range(0,1)=0.45;
void fragment() {
    ALBEDO=tint.rgb;
    ALPHA=opacity;
    ROUGHNESS=0.24;
}
