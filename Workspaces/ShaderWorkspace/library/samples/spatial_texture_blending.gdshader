// Texture Blending
// Uniform blend between an optional texture and a self-contained secondary surface.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture=false;
uniform float texture_scale : hint_range(0.1,20)=4;
uniform float blend : hint_range(0,1)=0.5;
// Integer lattice hashing avoids discontinuities caused by GPU sine/FMA precision.
float hash21(vec2 p) {
    ivec2 lattice=ivec2(floor(p));
    uint value=uint(lattice.x)*uint(374761393)+uint(lattice.y)*uint(668265263);
    value=(value ^ (value >> uint(13)))*uint(1274126177);
    value=value ^ (value >> uint(16));
    return float(value & uint(16777215))/16777215.0;
}
float noise2(vec2 p) {
    vec2 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
float fbm(vec2 p) {
    float s=0.0, a=0.5;
    for(int i=0;i<5;i++) {
        s+=a*noise2(p);
        p=mat2(vec2(1.6,1.2),vec2(-1.2,1.6))*p;
        a*=0.5;
    }
    return s;
}
vec3 checker(vec2 uv) {
    return mix(vec3(0.12,0.2,0.3),vec3(0.65,0.8,0.86),mod(floor(uv.x)+floor(uv.y),2.0));
}
void fragment() {
    vec3 a=use_texture?texture(source_texture,UV*texture_scale).rgb:checker(UV*texture_scale);
    vec3 b=mix(vec3(0.3,0.08,0.04),vec3(0.9,0.55,0.2),noise2(UV*20.0));
    ALBEDO=mix(a,b,blend);
    ROUGHNESS=0.6;
}
