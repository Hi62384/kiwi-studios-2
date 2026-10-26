// Triplanar Shader Template
// Reusable world position and normal varyings drive UV-independent three-axis projection.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float scale : hint_range(0.1,12)=3;
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
    // Sharpen normalized projection weights to reduce diagonal smearing.
    vec3 weights=pow(abs(world_normal),vec3(4));
    weights/=max(dot(weights,vec3(1)),0.001);
    vec3 p=world_pos*scale;
    ALBEDO=checker(p.yz)*weights.x+checker(p.xz)*weights.y+checker(p.xy)*weights.z;
    ROUGHNESS=0.7;
}
