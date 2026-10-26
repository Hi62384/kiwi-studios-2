// Snow Accumulation
// Soft snow coverage collects on upward surfaces with a broken irregular boundary.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float level : hint_range(-1,1.3)=0.4;
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
    float n=fbm(world_pos.xz*6.0);
    float snow=smoothstep(level-0.12,level+0.12,world_normal.y+n*0.25);
    ALBEDO=mix(vec3(0.2,0.14,0.1),vec3(0.92,0.96,1),snow);
    ROUGHNESS=mix(0.7,0.9,snow);
}
