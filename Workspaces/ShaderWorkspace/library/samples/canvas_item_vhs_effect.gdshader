// VHS Effect
// Analog tracking tear, chroma delay and moving tape grain over the rendered scene.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
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
    float jitter=(noise2(vec2(UV.y*180.0,TIME*15.0))-0.5)*0.008;
    float tear=pow(0.5+0.5*sin(UV.y*5.0-TIME),40.0)*0.05;
    vec2 uv=SCREEN_UV+vec2(jitter+tear,0);
    vec3 c=texture(screen_texture,uv).rgb;
    c.r=texture(screen_texture,uv+vec2(0.005,0)).r;
    c.b=texture(screen_texture,uv-vec2(0.005,0)).b;
    float noise=hash21(UV*1000.0+TIME)*0.1-0.05;
    COLOR=vec4(c+noise,1);
}
