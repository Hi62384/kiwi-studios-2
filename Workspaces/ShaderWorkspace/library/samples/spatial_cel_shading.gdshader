// Cel Shading
// Hard two-tone diffuse and stylized hard-edged specular lighting.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 color : source_color=vec4(0.85,0.35,0.13,1);
uniform float shadow_edge : hint_range(0,1)=0.45;
void fragment() {
    ALBEDO=color.rgb;
}
void light() {
    float d=step(shadow_edge,dot(NORMAL,LIGHT));
    DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*ATTENUATION*(0.12+0.88*d);
    float h=step(0.985,dot(NORMAL,normalize(LIGHT+VIEW)));
    SPECULAR_LIGHT+=h*ATTENUATION*LIGHT_COLOR;
}
