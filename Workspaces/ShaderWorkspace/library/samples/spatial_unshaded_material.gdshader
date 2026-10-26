// Unshaded Material
// Flat surface color unaffected by lights, suited to labels and stylized props.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color=vec4(0.7,0.2,0.5,1);
void fragment() {
    ALBEDO=base_color.rgb;
}
