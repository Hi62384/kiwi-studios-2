// Sand
// Soft wind ripples and subpixel granular variation create dry dune sand.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
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
    vec2 p=UV*20.0;
    float dune=sin(p.y*2.0+sin(p.x*0.4)*2.0);
    float grains=hash21(floor(UV*500.0));
    ALBEDO=mix(vec3(0.58,0.39,0.18),vec3(0.88,0.72,0.43),0.45+dune*0.15+grains*0.25);
    ROUGHNESS=0.88;
    NORMAL_MAP=normalize(vec3(0,cos(p.y*2.0)*0.15,1))*0.5+0.5;
}
