// Flowing Water
// Downstream streaks, lateral meanders and foam form a continuous flowing river.
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
    vec2 p=UV*vec2(7,20)+vec2(sin(UV.y*8.0+TIME)*0.4,TIME*3.0);
    float n=fbm(p);
    float foam=smoothstep(0.62,0.76,n);
    COLOR=vec4(mix(vec3(0.02,0.19,0.27),vec3(0.17,0.61,0.68),n)+foam*0.65,1);
}
