// Toon Shader Template
// Complete custom light processor with adjustable diffuse bands and correct accumulation.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.45,0.65,0.2,1);
uniform float steps : hint_range(2,8,1)=3;
void fragment() {
    ALBEDO=base_color.rgb;
    ROUGHNESS=1.0;
}
void light() {
    // Accumulate per light; ATTENUATION contains shadows and distance falloff.
    float ndl=max(dot(NORMAL,LIGHT),0.0);
    float band=floor(ndl*steps)/max(steps-1.0,1.0);
    DIFFUSE_LIGHT+=ALBEDO*clamp(band,0.0,1.0)*LIGHT_COLOR*ATTENUATION;
}
