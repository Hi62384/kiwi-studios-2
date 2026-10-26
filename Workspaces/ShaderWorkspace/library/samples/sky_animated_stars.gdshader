// Animated Stars
// Independently phased stellar twinkling keeps star positions fixed.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform float speed : hint_range(0.1,8)=2;
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
float stars(vec2 uv,float star_density) {
    vec2 p=uv*star_density;
    vec2 i=floor(p),f=fract(p);
    float h=hash21(i);
    vec2 center=vec2(hash21(i+12.3),hash21(i+47.8))*0.6+0.2;
    return (1.0-smoothstep(0.012,0.05,length(f-center)))*step(0.88,h);
}
void sky() {
    float s=stars(SKY_COORDS,180.0);
    float phase=hash21(floor(SKY_COORDS*180.0))*TAU;
    float twinkle=0.4+0.6*pow(0.5+0.5*sin(TIME*speed+phase),2.0);
    COLOR=vec3(0.005,0.008,0.025)+vec3(0.7,0.8,1)*s*twinkle*3.0;
}
