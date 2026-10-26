// Rough Surface
// Matte microsurface with fine irregular pores and nearly diffuse highlights.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.22,0.58,0.72,1);
uniform float roughness : hint_range(0,1)=0.45;
uniform float metallic : hint_range(0,1)=0;
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
    float n=noise2(UV*100.0);
    ALBEDO=base_color.rgb*(0.85+0.15*n);
    ROUGHNESS=0.8+0.2*n;
    NORMAL_MAP=normalize(vec3((n-0.5)*0.15,(noise2(UV*100.0+0.01)-0.5)*0.15,1))*0.5+0.5;
}
