// Swirling Fog
// Helical vortex density rotates around a vertical axis inside a soft boundary.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    vec3 p=(UVW-0.5)*2.0;
    float r=length(p.xz);
    float angle=atan(p.z,p.x);
    float spiral=0.5+0.5*sin(angle*3.0-r*12.0+p.y*4.0+TIME*1.4);
    DENSITY=density*spiral*(1.0-smoothstep(0.55,1.0,r));
    ALBEDO=fog_color.rgb;
}
