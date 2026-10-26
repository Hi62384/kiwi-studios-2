// Wet Surface
// Irregular wet patches darken porous ground and produce glossy puddle reflections.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float coverage : hint_range(0,1)=0.42;
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
void fragment() {
    float wet=smoothstep(coverage-0.1,coverage+0.1,fbm(UV*5.0));
    vec3 base=mix(vec3(0.25,0.19,0.13),vec3(0.55,0.5,0.4),noise2(UV*80.0));
    ALBEDO=base*mix(1.0,0.45,wet);
    ROUGHNESS=mix(0.92,0.08,wet);
    CLEARCOAT=wet;
    CLEARCOAT_ROUGHNESS=0.1;
}
