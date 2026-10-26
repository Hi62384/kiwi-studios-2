// Outline Highlight
// Surface-space silhouette highlighting using grazing normals; does not extrude mesh geometry.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.15,0.25,0.32,1);
uniform vec4 outline_color : source_color=vec4(1,0.7,0.1,1);
uniform float width : hint_range(0.01,0.8)=0.3;
void fragment() {
    float edge=1.0-smoothstep(0.0,width,abs(dot(NORMAL,VIEW)));
    ALBEDO=mix(base_color.rgb,outline_color.rgb,edge);
    EMISSION=outline_color.rgb*edge*0.4;
    ROUGHNESS=0.7;
}
