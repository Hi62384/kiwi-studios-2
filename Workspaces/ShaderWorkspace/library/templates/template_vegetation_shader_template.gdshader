// Vegetation Shader Template
// Root-weighted wind deformation and plant color variation with cutout guidance.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength : hint_range(0,0.8)=0.2;
uniform vec4 root_color : source_color=vec4(0.07,0.2,0.02,1);
uniform vec4 tip_color : source_color=vec4(0.4,0.6,0.12,1);
void vertex() {
    // UV.y=1 is rooted; UV.y=0 is the free tip on a foliage card.
    float weight=pow(1.0-UV.y,2.0);
    VERTEX.x+=sin(TIME*2.0+VERTEX.x*3.0)*wind_strength*weight;
}
void fragment() {
    ALBEDO=mix(root_color.rgb,tip_color.rgb,1.0-UV.y);
    ROUGHNESS=0.9;
    // Add an alpha texture here for cutout foliage; use ALPHA_SCISSOR_THRESHOLD.
}
