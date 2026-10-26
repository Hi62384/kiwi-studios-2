// Moving Clouds
// Wind-advected fractal cloud layer with stable world direction and perspective.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform vec2 wind=vec2(0.035,0.01);
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
    vec2 p=EYEDIR.xz/max(EYEDIR.y+0.15,0.05)*2.0+TIME*wind;
    float n=fbm(p);
    float cloud=smoothstep(0.4,0.68,n)*smoothstep(0.0,0.15,EYEDIR.y);
    COLOR=mix(mix(vec3(0.65,0.79,0.92),vec3(0.08,0.25,0.57),max(EYEDIR.y,0.0)),vec3(0.96,0.98,1),cloud);
}
