// Simple Cloud Layer
// A planar cloud layer projected into the sky with a soft horizon fade.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
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
    vec3 c=mix(vec3(0.55,0.76,0.92),vec3(0.1,0.3,0.62),max(EYEDIR.y,0.0));
    vec2 p=EYEDIR.xz/max(EYEDIR.y,0.08)*2.0;
    float cloud=smoothstep(0.45,0.7,noise2(p))*smoothstep(0.0,0.2,EYEDIR.y);
    COLOR=mix(c,vec3(0.94,0.95,1),cloud);
}
