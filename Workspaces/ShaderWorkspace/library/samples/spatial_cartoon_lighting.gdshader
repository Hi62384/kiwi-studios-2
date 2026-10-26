// Cartoon Lighting
// Wrapped cartoon diffuse shading with a broad cream-colored highlight.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
void fragment() {
    ALBEDO=vec3(0.7,0.32,0.22);
}
void light() {
    float wrap=clamp((dot(NORMAL,LIGHT)+0.35)/1.35,0.0,1.0);
    float tone=smoothstep(0.3,0.4,wrap)*0.7+0.3;
    DIFFUSE_LIGHT+=ALBEDO*tone*ATTENUATION*LIGHT_COLOR;
    float h=smoothstep(0.9,0.93,dot(NORMAL,normalize(LIGHT+VIEW)));
    SPECULAR_LIGHT+=vec3(1,0.9,0.6)*h*ATTENUATION*LIGHT_COLOR;
}
