// Triplanar Texturing
// World-space three-axis texture projection blended by normal, requiring no UV unwrap.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture=false;
uniform float texture_scale : hint_range(0.1,20)=4;
uniform float sharpness : hint_range(1,12)=4;
varying vec3 world_pos;
varying vec3 world_normal;
vec3 checker(vec2 uv) {
    return mix(vec3(0.12,0.2,0.3),vec3(0.65,0.8,0.86),mod(floor(uv.x)+floor(uv.y),2.0));
}
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec3 w=pow(abs(world_normal),vec3(sharpness));
    w/=max(w.x+w.y+w.z,0.001);
    vec3 p=world_pos*texture_scale;
    vec3 x=use_texture?texture(source_texture,p.yz).rgb:checker(p.yz);
    vec3 y=use_texture?texture(source_texture,p.xz).rgb:checker(p.xz);
    vec3 z=use_texture?texture(source_texture,p.xy).rgb:checker(p.xy);
    ALBEDO=x*w.x+y*w.y+z*w.z;
    ROUGHNESS=0.7;
}
