// Transparent Material Template
// Explicit alpha-blended material starter with transparent sorting guidance.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled,depth_draw_always;
uniform vec4 tint : source_color=vec4(0.2,0.65,0.8,1);
uniform float opacity : hint_range(0,1)=0.4;
void fragment() {
    ALBEDO=tint.rgb;
    ALPHA=tint.a*opacity;
    ROUGHNESS=0.2;
    // Writing ALPHA uses the transparent pipeline. Overlapping surfaces may sort.
}
