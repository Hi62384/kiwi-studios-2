// Height Based Texture Blending
// Height-aware material transition preserves raised islands instead of a muddy linear mix.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float blend : hint_range(0,1)=0.45;
uniform float softness : hint_range(0.01,0.4)=0.07;
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
    float a=fbm(UV*8.0),b=noise2(UV*35.0);
    float mask=smoothstep(blend-softness,blend+softness,a-b*0.25);
    ALBEDO=mix(vec3(0.18,0.1,0.055)*(0.6+b),vec3(0.56,0.58,0.5)*(0.6+a),mask);
    ROUGHNESS=mix(0.9,0.55,mask);
}
