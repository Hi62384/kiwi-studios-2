// Space Background
// Cloudy galactic band with colored nebulae and an independent sharp star field.
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
float stars(vec2 uv,float star_density) {
    vec2 p=uv*star_density;
    vec2 i=floor(p),f=fract(p);
    float h=hash21(i);
    vec2 center=vec2(hash21(i+12.3),hash21(i+47.8))*0.6+0.2;
    return (1.0-smoothstep(0.012,0.05,length(f-center)))*step(0.88,h);
}
void sky() {
    vec3 direction=EYEDIR*5.0;
    float warp=fbm(direction.yz);
    float n=0.65*fbm(direction.xy+warp)+0.35*fbm(direction.zx-warp);
    float band=exp(-pow(dot(EYEDIR,normalize(vec3(0.15,1.0,0.2)))*5.0,2.0));
    vec3 nebula=mix(vec3(0.07,0.015,0.17),vec3(0.1,0.4,0.55),n);
    COLOR=nebula*n*band+stars(SKY_COORDS,240.0)*1.8;
}
