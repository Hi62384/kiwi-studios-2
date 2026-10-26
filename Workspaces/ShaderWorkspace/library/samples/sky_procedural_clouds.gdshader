// Procedural Clouds
// Layered domain-warped cloud bodies include darker undersides and bright tops.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform float coverage : hint_range(0.1,0.8)=0.42;
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
void sky() {
    vec2 p=EYEDIR.xz/max(EYEDIR.y+0.2,0.08)*2.0;
    float n=fbm(p+fbm(p*1.7));
    float cloud=smoothstep(coverage,coverage+0.22,n)*smoothstep(0.0,0.1,EYEDIR.y);
    vec3 c=mix(vec3(0.6,0.76,0.94),vec3(0.08,0.27,0.6),max(EYEDIR.y,0.0));
    vec3 shade=mix(vec3(0.5,0.58,0.7),vec3(1),smoothstep(0.5,0.8,n));
    COLOR=mix(c,shade,cloud);
}
