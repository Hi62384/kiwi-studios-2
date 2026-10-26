// Mud
// Uneven earth clumps surround darker glossy pools in wet mud.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
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
    float clumps=fbm(UV*9.0);
    float puddle=1.0-smoothstep(0.3,0.43,clumps);
    ALBEDO=mix(vec3(0.26,0.14,0.06),vec3(0.075,0.055,0.035),puddle)*(0.7+clumps*0.6);
    ROUGHNESS=mix(0.94,0.12,puddle);
    CLEARCOAT=puddle;
}
