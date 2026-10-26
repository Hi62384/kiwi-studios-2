// Moss Coverage
// Clustered moss with fine filaments favors upward-facing stone surfaces.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float coverage : hint_range(0,1)=0.55;
varying vec3 world_pos;
varying vec3 world_normal;
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
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    float clump=fbm(world_pos.xz*9.0+world_pos.y);
    float m=smoothstep(coverage-0.1,coverage+0.1,clump+max(world_normal.y,0.0)*0.2);
    float fibre=noise2(UV*160.0);
    ALBEDO=mix(vec3(0.25,0.27,0.25),mix(vec3(0.07,0.16,0.015),vec3(0.35,0.48,0.06),fibre),m);
    ROUGHNESS=0.95;
}
