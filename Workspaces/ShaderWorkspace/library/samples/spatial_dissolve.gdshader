// Dissolve
// 3D cutout dissolution with a hot edge and depth-writing opaque survivors.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float amount : hint_range(0,1)=0.43;
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
    float n=fbm(UV*12.0);
    ALBEDO=vec3(0.25,0.48,0.55);
    ALPHA=step(amount,n);
    ALPHA_SCISSOR_THRESHOLD=0.5;
    EMISSION=vec3(1,0.2,0.02)*(1.0-smoothstep(amount,amount+0.04,n))*3.0;
    ROUGHNESS=0.65;
}
