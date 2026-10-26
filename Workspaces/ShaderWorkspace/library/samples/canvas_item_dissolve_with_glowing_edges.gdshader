// Dissolve With Glowing Edges
// Burn-away dissolve with a bright boundary controlled independently of the cutout.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float amount : hint_range(0,1)=0.4;
uniform float width : hint_range(0.01,0.2)=0.06;
uniform vec4 edge_color : source_color=vec4(1,0.35,0.03,1);
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
    float n=fbm(UV*12.0);
    float visible=smoothstep(amount,amount+0.01,n);
    float edge=1.0-smoothstep(amount,amount+width,n);
    COLOR=vec4(c.rgb+edge*edge_color.rgb*3.0,c.a*visible);
}
