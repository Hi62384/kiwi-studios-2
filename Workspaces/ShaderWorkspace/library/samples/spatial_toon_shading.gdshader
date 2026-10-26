// Toon Shading
// Quantized diffuse lighting with multiple light bands and independent light attenuation.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 color : source_color=vec4(0.3,0.7,0.8,1);
uniform float bands : hint_range(2,8,1)=3;
void fragment() {
    ALBEDO=color.rgb;
    ROUGHNESS=1.0;
}
void light() {
    float ndl=max(dot(NORMAL,LIGHT),0.0);
    float ramp=floor(ndl*bands)/max(bands-1.0,1.0);
    DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*ATTENUATION*clamp(ramp,0.0,1.0);
}
