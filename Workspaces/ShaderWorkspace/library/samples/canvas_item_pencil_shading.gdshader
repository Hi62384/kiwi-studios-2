// Pencil Shading
// Directional graphite fibers follow source shading over warm paper grain.
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
    vec4 c=texture(TEXTURE,UV);
    float l=dot(c.rgb,vec3(0.3,0.59,0.11));
    float fibres=noise2(UV*vec2(500,35));
    float hatch=sin((UV.x+UV.y*0.6)*700.0+noise2(UV*25.0)*2.0)*0.5+0.5;
    float lead=clamp((1.0-l)*(0.45+fibres*0.8+hatch*0.25),0.0,1.0);
    COLOR=vec4(mix(vec3(0.94,0.92,0.86),vec3(0.12),lead),c.a);
}
