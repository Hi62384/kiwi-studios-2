// Fire Effect
// Tapered turbulent flame with a hot core and transparent outer tongues.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
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
    vec2 p=vec2(UV.x,1.0-UV.y);
    float n=fbm(vec2(p.x*7.0,p.y*5.0+TIME*2.0));
    float flame=clamp((1.0-p.y)*1.7-abs(p.x-0.5)*2.5+n*0.7-0.6,0.0,1.0);
    vec3 c=mix(vec3(0.9,0.04,0),vec3(1,0.8,0.12),smoothstep(0.1,0.7,flame));
    COLOR=vec4(c*1.4,smoothstep(0.02,0.2,flame));
}
