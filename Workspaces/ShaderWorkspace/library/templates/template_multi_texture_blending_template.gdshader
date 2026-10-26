// Multi Texture Blending Template
// Two optional texture slots with a reusable mask and working texture-free appearance.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D texture_a : source_color,repeat_enable;
uniform sampler2D texture_b : source_color,repeat_enable;
uniform bool use_textures=false;
uniform float texture_scale : hint_range(0.1,12)=4;
uniform float blend : hint_range(0,1)=0.5;
vec3 checker(vec2 uv) {
    return mix(vec3(0.12,0.2,0.3),vec3(0.65,0.8,0.86),mod(floor(uv.x)+floor(uv.y),2.0));
}
void fragment() {
    vec2 uv=UV*texture_scale;
    // Supply both textures and enable the flag to replace the procedural fallbacks.
    vec3 a=use_textures?texture(texture_a,uv).rgb:checker(uv);
    vec3 b=use_textures?texture(texture_b,uv).rgb:vec3(0.7,0.3,0.1);
    float mask=smoothstep(blend-0.15,blend+0.15,UV.y);
    ALBEDO=mix(a,b,mask);
    ROUGHNESS=mix(0.3,0.8,mask);
}
