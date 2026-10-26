// Procedural Noise Shader Template
// Self-contained value-noise and fractal helpers with deterministic coordinate offsets.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float scale : hint_range(0.1,40)=8;
uniform vec2 seed_offset=vec2(3.1,7.4);
uniform vec4 low_color : source_color=vec4(0.1,0.15,0.2,1);
uniform vec4 high_color : source_color=vec4(0.8,0.9,1,1);
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
    // Replace fbm with noise2 for a cheaper single octave.
    float value=fbm(UV*scale+seed_offset);
    ALBEDO=mix(low_color.rgb,high_color.rgb,value);
    ROUGHNESS=0.8;
}
