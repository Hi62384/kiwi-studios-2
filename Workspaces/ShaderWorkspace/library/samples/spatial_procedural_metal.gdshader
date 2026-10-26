// Procedural Metal
// Directional brushed metal with sparse long scratches and anisotropic highlights.
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
    vec2 p=UV*vec2(8,700);
    float brush=noise2(p);
    float scratch=step(0.97,hash21(floor(UV*vec2(30,400))))*step(fract(UV.x*30.0),0.75);
    ALBEDO=vec3(0.63,0.67,0.7)*(0.8+brush*0.2)-scratch*0.12;
    ROUGHNESS=0.22+brush*0.28;
    METALLIC=1.0;
    ANISOTROPY=0.8;
    ANISOTROPY_FLOW=vec2(1,0);
}
