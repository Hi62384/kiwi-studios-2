// Procedural Wood
// Directional growth rings bend around a knot, with fine elongated wood fibers.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float density : hint_range(3,40)=18;
uniform float distortion : hint_range(0,3)=1;
uniform vec4 light_wood : source_color=vec4(0.65,0.36,0.14,1);
uniform vec4 dark_wood : source_color=vec4(0.22,0.08,0.025,1);
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
    vec2 p=UV*vec2(density,2.0);
    float knot=length((UV-vec2(0.4,0.6))*vec2(1,3));
    float bend=fbm(p*0.7)*distortion+exp(-knot*10.0)*2.0;
    float grain=pow(0.5+0.5*sin((p.x+bend)*TAU),3.0);
    float fine=noise2(UV*vec2(450,18));
    ALBEDO=mix(light_wood.rgb,dark_wood.rgb,grain*0.7+(1.0-fine)*0.18);
    ROUGHNESS=0.52+grain*0.18;
}
